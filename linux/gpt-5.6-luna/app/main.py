from __future__ import annotations

import asyncio
import json
import logging
import mimetypes
import os
import struct
import sqlite3
import subprocess
import threading
import time
import uuid
import wave
from array import array
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, HTTPException, Query, Request, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


DATA_DIR = Path(os.environ.get("VT_DATA_DIR", "/data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)
FILES_DIR = DATA_DIR / "files"
FILES_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "voice-transcribe.sqlite3"
STATIC_DIR = Path(__file__).parent / "static"
MAX_UPLOAD_BYTES = int(os.environ.get("VT_MAX_UPLOAD_BYTES", str(500 * 1024 * 1024)))
MAX_CONCURRENT_FILE_JOBS = max(1, int(os.environ.get("VT_MAX_CONCURRENT_FILE_JOBS", "2")))
SUPPORTED_EXTENSIONS = {"wav", "m4a", "mp3", "flac", "ogg", "webm", "mp4", "avi", "mov"}
ASR_ENGINE = os.environ.get("VT_ASR_ENGINE", "fake").lower()
ASR_MODEL = os.environ.get("VT_ASR_MODEL", "small.en")
ASR_COMPUTE_TYPE = os.environ.get("VT_ASR_COMPUTE_TYPE", "int8")
APP_VERSION = os.environ.get("VT_VERSION", "0.1.0")
APP_BUILD = os.environ.get("VT_BUILD", "1")
LOG_LEVEL = os.environ.get("VT_LOG_LEVEL", "INFO").upper()

# Field names whose values must never reach the log stream.
REDACTED_LOG_FIELDS = {"text", "transcript", "content", "audio", "originalPath", "normalizedPath", "originalName"}
REDACTED_LOG_VALUE = "[redacted]"


class JsonLogFormatter(logging.Formatter):
    """Render one JSON object per line so container log collectors can parse records."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname.lower(),
            "event": record.getMessage(),
        }
        fields = getattr(record, "fields", None)
        if isinstance(fields, dict):
            payload.update(fields)
        return json.dumps(payload, default=str)


LOGGER = logging.getLogger("voicetranscribe")
LOGGER.handlers.clear()
_log_handler = logging.StreamHandler()
_log_handler.setFormatter(JsonLogFormatter())
LOGGER.addHandler(_log_handler)
LOGGER.setLevel(LOG_LEVEL)
# Root has no handlers outside tests, so records print once but caplog can still observe them.
LOGGER.propagate = True


def log_event(level: str, event: str, **fields: Any) -> None:
    safe_fields = {
        name: (REDACTED_LOG_VALUE if name in REDACTED_LOG_FIELDS else value)
        for name, value in fields.items()
    }
    LOGGER.log(getattr(logging, level.upper(), logging.INFO), event, extra={"fields": safe_fields})


_whisper_model: Any = None
_whisper_model_lock = threading.Lock()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class SessionCreate(BaseModel):
    source_name: str = Field(default="Browser microphone", min_length=1, max_length=200)
    sample_rate: int = Field(default=16_000, ge=8_000, le=96_000)
    channels: int = Field(default=1, ge=1, le=2)


class SessionCommand(BaseModel):
    request_id: str | None = None


@dataclass
class FileSource:
    id: str
    original_name: str
    original_path: Path
    normalized_path: Path | None
    size_bytes: int
    duration: float | None
    sample_rate: int | None
    channels: int | None
    format_name: str
    status: str = "ready"
    progress: float = 1.0
    error: str | None = None
    session_id: str | None = None
    job_id: str | None = None

    def snapshot(self) -> dict[str, Any]:
        linked_session = sessions.get(self.session_id) if self.session_id else None
        return {
            "id": self.id,
            "name": self.original_name,
            "sizeBytes": self.size_bytes,
            "duration": self.duration,
            "sampleRate": self.sample_rate,
            "channels": self.channels,
            "format": self.format_name,
            "status": self.status,
            "progress": self.progress,
            "error": self.error,
            "sessionId": self.session_id,
            "jobId": self.job_id,
            "audioUrl": f"/api/files/{self.id}/audio",
            "transcript": linked_session.finalized_segments if linked_session else [],
        }


@dataclass
class Session:
    id: str
    source_name: str
    sample_rate: int
    channels: int
    created_at: str
    state: str = "created"
    recording: bool = False
    transcribing: bool = False
    paused: bool = False
    audio_bytes: int = 0
    next_sequence: int = 1
    transcript_index: int = 0
    finalized_segments: list[dict[str, Any]] = field(default_factory=list)
    events: list[dict[str, Any]] = field(default_factory=list)
    clients: set[WebSocket] = field(default_factory=set)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    audio_file: Any = None
    recording_started_at: float | None = None
    live_pcm: bytearray = field(default_factory=bytearray)
    live_asr_bytes: int = 0
    live_asr_task: asyncio.Task[Any] | None = None
    asr_status: str = "idle"
    asr_windows_processed: int = 0
    asr_last_error: str | None = None

    def snapshot(self) -> dict[str, Any]:
        return {
            "sessionId": self.id,
            "sourceName": self.source_name,
            "sampleRate": self.sample_rate,
            "channels": self.channels,
            "createdAt": self.created_at,
            "state": self.state,
            "recording": self.recording,
            "transcribing": self.transcribing,
            "paused": self.paused,
            "transcript": self.finalized_segments,
            "asrStatus": self.asr_status,
            "asrWindowsProcessed": self.asr_windows_processed,
            "asrLastError": self.asr_last_error,
        }


sessions: dict[str, Session] = {}
file_sources: dict[str, FileSource] = {}
file_job_semaphore = asyncio.Semaphore(MAX_CONCURRENT_FILE_JOBS)


def initialize_database() -> None:
    with sqlite3.connect(DB_PATH) as database:
        database.executescript(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                source_name TEXT NOT NULL,
                sample_rate INTEGER NOT NULL,
                channels INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                state TEXT NOT NULL,
                recording INTEGER NOT NULL,
                transcribing INTEGER NOT NULL,
                paused INTEGER NOT NULL,
                transcript_json TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS file_sources (
                id TEXT PRIMARY KEY,
                original_name TEXT NOT NULL,
                original_path TEXT NOT NULL,
                normalized_path TEXT,
                size_bytes INTEGER NOT NULL,
                duration REAL,
                sample_rate INTEGER,
                channels INTEGER,
                format_name TEXT NOT NULL,
                status TEXT NOT NULL,
                progress REAL NOT NULL,
                error TEXT,
                session_id TEXT,
                updated_at TEXT NOT NULL
            );
            """
        )


def persist_session(session: Session) -> None:
    snapshot = session.snapshot()
    with sqlite3.connect(DB_PATH) as database:
        database.execute(
            """
            INSERT INTO sessions (
                id, source_name, sample_rate, channels, created_at, state,
                recording, transcribing, paused, transcript_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                source_name=excluded.source_name,
                sample_rate=excluded.sample_rate,
                channels=excluded.channels,
                state=excluded.state,
                recording=excluded.recording,
                transcribing=excluded.transcribing,
                paused=excluded.paused,
                transcript_json=excluded.transcript_json,
                updated_at=excluded.updated_at
            """,
            (
                session.id,
                session.source_name,
                session.sample_rate,
                session.channels,
                session.created_at,
                session.state,
                int(session.recording),
                int(session.transcribing),
                int(session.paused),
                json.dumps(snapshot["transcript"]),
                now_iso(),
            ),
        )


def persist_file_source(source: FileSource) -> None:
    with sqlite3.connect(DB_PATH) as database:
        database.execute(
            """
            INSERT INTO file_sources (
                id, original_name, original_path, normalized_path, size_bytes,
                duration, sample_rate, channels, format_name, status, progress,
                error, session_id, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                normalized_path=excluded.normalized_path,
                status=excluded.status,
                progress=excluded.progress,
                error=excluded.error,
                session_id=excluded.session_id,
                updated_at=excluded.updated_at
            """,
            (
                source.id,
                source.original_name,
                str(source.original_path),
                str(source.normalized_path) if source.normalized_path else None,
                source.size_bytes,
                source.duration,
                source.sample_rate,
                source.channels,
                source.format_name,
                source.status,
                source.progress,
                source.error,
                source.session_id,
                now_iso(),
            ),
        )


def load_persistent_state() -> None:
    with sqlite3.connect(DB_PATH) as database:
        for row in database.execute(
            "SELECT id, source_name, sample_rate, channels, created_at, state, recording, transcribing, paused, transcript_json FROM sessions"
        ):
            session = Session(
                id=row[0], source_name=row[1], sample_rate=row[2], channels=row[3],
                created_at=row[4], state=row[5], recording=False,
                transcribing=False, paused=False,
            )
            session.finalized_segments = json.loads(row[9])
            session.transcript_index = len(session.finalized_segments)
            sessions[session.id] = session
        for row in database.execute(
            "SELECT id, original_name, original_path, normalized_path, size_bytes, duration, sample_rate, channels, format_name, status, progress, error, session_id FROM file_sources"
        ):
            original_path = Path(row[2])
            normalized_path = Path(row[3]) if row[3] else None
            if not original_path.exists():
                continue
            status = row[9]
            error = row[11]
            if status in {"queued", "loading", "normalizing", "transcribing", "finalizing"}:
                status = "failed"
                error = "Processing was interrupted by a service restart"
            source = FileSource(
                id=row[0], original_name=row[1], original_path=original_path,
                normalized_path=normalized_path, size_bytes=row[4], duration=row[5],
                sample_rate=row[6], channels=row[7], format_name=row[8],
                status=status, progress=row[10], error=error, session_id=row[12],
            )
            file_sources[source.id] = source


initialize_database()
load_persistent_state()


async def publish(session: Session, event_type: str, payload: dict[str, Any]) -> dict[str, Any]:
    async with session.lock:
        event = {
            "type": event_type,
            "sessionId": session.id,
            "sequence": session.next_sequence,
            "occurredAt": now_iso(),
            "payload": payload,
        }
        session.next_sequence += 1
        session.events.append(event)
        # Keep reconnect replay bounded while retaining enough state for normal reconnects.
        if len(session.events) > 2_000:
            session.events = session.events[-2_000:]
        clients = list(session.clients)

    stale: list[WebSocket] = []
    for client in clients:
        try:
            await client.send_json(event)
        except Exception:
            stale.append(client)
    if stale:
        async with session.lock:
            for client in stale:
                session.clients.discard(client)
    return event


def get_session(session_id: str) -> Session:
    session = sessions.get(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


def audio_path(session: Session) -> Path:
    return DATA_DIR / f"{session.id}.pcm"


def normalized_file_path(file_id: str) -> Path:
    return FILES_DIR / f"{file_id}-16k-mono.wav"


def remove_artifact(path: Path | None) -> None:
    if path is None:
        return
    resolved = path.resolve()
    data_root = DATA_DIR.resolve()
    if data_root not in resolved.parents:
        raise RuntimeError("Refusing to remove an artifact outside the data directory")
    resolved.unlink(missing_ok=True)


def delete_session_data(session: Session) -> None:
    if session.audio_file is not None:
        session.audio_file.close()
        session.audio_file = None
    remove_artifact(audio_path(session))
    remove_artifact(DATA_DIR / f"{session.id}-live-window.wav")
    with sqlite3.connect(DB_PATH) as database:
        database.execute("DELETE FROM sessions WHERE id = ?", (session.id,))
    sessions.pop(session.id, None)


def probe_media(path: Path) -> tuple[float | None, int | None, int | None, str | None]:
    """Read media metadata through ffprobe; return unknown values if probing fails."""
    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "error", "-show_entries",
                "format=duration:stream=sample_rate,channels,codec_name",
                "-of", "json", str(path),
            ],
            capture_output=True, text=True, timeout=20, check=True,
        )
        document = json.loads(result.stdout)
        format_data = document.get("format", {})
        stream = next(iter(document.get("streams", [])), {})
        raw_duration = format_data.get("duration")
        duration = float(raw_duration) if raw_duration not in (None, "N/A") else None
        raw_rate = stream.get("sample_rate")
        sample_rate = int(raw_rate) if raw_rate not in (None, "N/A") else None
        raw_channels = stream.get("channels")
        channels = int(raw_channels) if raw_channels not in (None, "N/A") else None
        codec = stream.get("codec_name")
        return duration, sample_rate, channels, codec
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError, json.JSONDecodeError):
        return None, None, None, None


def normalize_media(source: FileSource) -> None:
    output = normalized_file_path(source.id)
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-i", str(source.original_path),
             "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(output)],
            capture_output=True, text=True, timeout=300, check=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise RuntimeError("FFmpeg could not decode or normalize this file") from error
    source.normalized_path = output
    source.status = "ready"
    source.progress = 1.0
    persist_file_source(source)


async def normalize_media_async(source: FileSource) -> None:
    source.status = "normalizing"
    source.progress = 0.1
    persist_file_source(source)
    await asyncio.to_thread(normalize_media, source)


def create_file_session(source: FileSource) -> Session:
    session_id = str(uuid.uuid4())
    session = Session(
        id=session_id,
        source_name=source.original_name,
        sample_rate=16000,
        channels=1,
        created_at=now_iso(),
        state="transcribing",
        transcribing=True,
    )
    sessions[session_id] = session
    source.session_id = session_id
    persist_session(session)
    persist_file_source(source)
    return session


def faster_whisper_available() -> bool:
    try:
        import faster_whisper  # noqa: F401
        return True
    except Exception:
        return False


def whisper_model() -> Any:
    global _whisper_model
    if _whisper_model is None:
        with _whisper_model_lock:
            if _whisper_model is None:
                from faster_whisper import WhisperModel
                _whisper_model = WhisperModel(
                    ASR_MODEL,
                    device="auto",
                    compute_type=ASR_COMPUTE_TYPE,
                    download_root=str(DATA_DIR / "models"),
                )
                log_event("info", "asr.model.loaded", model=ASR_MODEL, computeType=ASR_COMPUTE_TYPE)
    return _whisper_model


def write_float32_wav(path: Path, audio: bytes, sample_rate: int, channels: int) -> None:
    floats = array("f")
    floats.frombytes(audio)
    int_samples = [max(-32768, min(32767, int(sample * 32767))) for sample in floats]
    pcm = struct.pack(f"<{len(int_samples)}h", *int_samples)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(pcm)


def transcribe_with_faster_whisper(path: Path) -> list[dict[str, Any]]:
    model = whisper_model()
    segments, _ = model.transcribe(
        str(path),
        beam_size=5,
        vad_filter=True,
        word_timestamps=True,
    )
    results: list[dict[str, Any]] = []
    for index, segment in enumerate(segments):
        text = segment.text.strip()
        if not text:
            continue
        results.append({
            "segmentId": str(uuid.uuid4()),
            "sentenceIndex": index,
            "text": text,
            "audioOffset": float(segment.start),
            "audioEndOffset": float(segment.end),
            "isFinal": True,
            "speaker": None,
        })
    return results


async def process_live_asr(session: Session, force: bool = False) -> None:
    chunk_bytes = session.sample_rate * session.channels * 4 * 10
    if not force and len(session.live_pcm) < chunk_bytes:
        return
    if not session.live_pcm:
        return
    audio = bytes(session.live_pcm[:chunk_bytes] if not force else session.live_pcm)
    del session.live_pcm[:len(audio)]
    base_offset = session.live_asr_bytes / (session.sample_rate * session.channels * 4)
    session.live_asr_bytes += len(audio)
    path = DATA_DIR / f"{session.id}-live-window.wav"
    try:
        await asyncio.to_thread(write_float32_wav, path, audio, session.sample_rate, session.channels)
        session.asr_status = "running"
        await publish(session, "asr.window.started", {"offset": base_offset, "duration": len(audio) / (session.sample_rate * session.channels * 4)})
        segments = await asyncio.to_thread(transcribe_with_faster_whisper, path)
        for segment in segments:
            segment["audioOffset"] = base_offset + float(segment["audioOffset"])
            session.transcript_index += 1
            segment["sentenceIndex"] = session.transcript_index - 1
            session.finalized_segments.append(segment)
            persist_session(session)
            await publish(session, "transcript.segment.final", segment)
        session.asr_windows_processed += 1
        session.asr_status = "ready"
        session.asr_last_error = None
        persist_session(session)
        await publish(session, "asr.window.completed", {"windows": session.asr_windows_processed, "segments": len(segments)})
    except Exception:
        session.asr_status = "failed"
        raise
    finally:
        path.unlink(missing_ok=True)


async def schedule_live_asr(session: Session) -> None:
    if ASR_ENGINE != "faster-whisper" or not session.transcribing or session.paused:
        return
    if session.live_asr_task is not None and not session.live_asr_task.done():
        return
    chunk_bytes = session.sample_rate * session.channels * 4 * 10
    if len(session.live_pcm) < chunk_bytes:
        return

    session.asr_status = "queued"
    await publish(session, "asr.window.queued", {"bytes": len(session.live_pcm)})

    async def run() -> None:
        try:
            await process_live_asr(session)
        except Exception as error:
            session.asr_status = "failed"
            session.asr_last_error = str(error)
            persist_session(session)
            await publish(session, "transcription.failed", {"error": str(error), "scope": "live"})
            log_event("error", "asr.window.failed", sessionId=session.id, scope="live", error=str(error))

    session.live_asr_task = asyncio.create_task(run())


async def drain_live_asr(session: Session) -> None:
    if session.live_asr_task is not None:
        await session.live_asr_task
        session.live_asr_task = None
    if ASR_ENGINE == "faster-whisper" and session.live_pcm:
        try:
            await process_live_asr(session, force=True)
        except Exception as error:
            await publish(session, "transcription.failed", {"error": str(error), "scope": "live"})
            log_event("error", "asr.window.failed", sessionId=session.id, scope="final", error=str(error))


async def transcribe_file(source: FileSource) -> None:
    async with file_job_semaphore:
        await _transcribe_file(source)


async def _transcribe_file(source: FileSource) -> None:
    source.status = "loading"
    source.progress = 0.0
    persist_file_source(source)
    session = create_file_session(source)
    await publish(session, "session.created", session.snapshot())
    started_at = time.perf_counter()
    log_event("info", "file.job.started", jobId=source.job_id, fileId=source.id, engine=ASR_ENGINE)
    try:
        if ASR_ENGINE == "faster-whisper":
            if not faster_whisper_available():
                raise RuntimeError("faster-whisper is not installed in this image")
            segments = await asyncio.to_thread(transcribe_with_faster_whisper, source.normalized_path)
        else:
            duration = source.duration or 0.0
            count = max(1, int((duration + 4.99) // 5))
            segments = [
                {
                    "segmentId": str(uuid.uuid4()),
                    "sentenceIndex": index,
                    "text": f"Demo file sentence {index + 1}.",
                    "audioOffset": index * 5.0,
                    "isFinal": True,
                    "speaker": None,
                }
                for index in range(count)
            ]
        source.status = "transcribing"
        source.progress = 0.1
        persist_file_source(source)
        for index, segment in enumerate(segments):
            session.transcript_index += 1
            session.finalized_segments.append(segment)
            persist_session(session)
            await publish(session, "transcript.segment.final", segment)
            source.progress = 0.1 + (0.8 * (index + 1) / max(1, len(segments)))
            persist_file_source(source)
        source.status = "finalizing"
        source.progress = 0.95
        persist_file_source(source)
    except Exception as error:
        session.transcribing = False
        session.state = "failed"
        source.status = "failed"
        source.error = str(error)
        persist_session(session)
        persist_file_source(source)
        await publish(session, "transcription.failed", {"error": source.error})
        log_event("error", "file.job.failed", jobId=source.job_id, fileId=source.id, sessionId=session.id, error=source.error, durationMs=round((time.perf_counter() - started_at) * 1000, 2))
        return
    session.transcribing = False
    session.state = "completed"
    source.status = "completed"
    source.progress = 1.0
    persist_session(session)
    persist_file_source(source)
    await publish(session, "transcription.completed", {"segments": len(session.finalized_segments), "engine": ASR_ENGINE})
    log_event("info", "file.job.completed", jobId=source.job_id, fileId=source.id, sessionId=session.id, segments=len(session.finalized_segments), durationMs=round((time.perf_counter() - started_at) * 1000, 2))


def markdown_for(session: Session) -> str:
    lines = [
        "# DETAILS",
        "",
        f"- Session: `{session.id}`",
        f"- Source: {session.source_name}",
        f"- Created: {session.created_at}",
        f"- Sample rate: {session.sample_rate} Hz",
        f"- Channels: {session.channels}",
        f"- State: {session.state}",
        f"- Exported: {now_iso()}",
        f"- Application: {APP_VERSION} (build {APP_BUILD})",
        "",
        "# RECORDING",
        "",
        "| Offset | Speaker | Text |",
        "|---:|---|---|",
    ]
    if session.finalized_segments:
        for segment in session.finalized_segments:
            text = segment["text"].replace("|", "\\|").replace("\n", " ")
            lines.append(f"| {segment['audioOffset']:.2f}s | {segment.get('speaker', '')} | {text} |")
    else:
        lines.append("| — | — | No finalized transcript segments. |")
    lines.extend([
        "",
        "# SUMMARY",
        "",
        "The first vertical slice uses a fake transcription adapter. Replace it with a real ASR adapter in the next implementation phase.",
        "",
        "# FILES",
        "",
        f"- Audio: `{audio_path(session).name}`",
    ])
    return "\n".join(lines) + "\n"


async def fake_finalize(session: Session, force: bool = False) -> None:
    if not session.transcribing or session.paused:
        return
    # Float32 mono audio uses four bytes per sample. Five seconds is enough to demonstrate
    # the event pipeline without pretending that fake text is a real recognition result.
    threshold = session.sample_rate * session.channels * 4 * 5
    while session.audio_bytes >= (session.transcript_index + 1) * threshold or (force and session.audio_bytes > session.transcript_index * threshold):
        session.transcript_index += 1
        offset = max(0.0, (session.transcript_index - 1) * 5.0)
        segment = {
            "segmentId": str(uuid.uuid4()),
            "sentenceIndex": session.transcript_index - 1,
            "text": f"Demo finalized sentence {session.transcript_index}.",
            "audioOffset": offset,
            "isFinal": True,
            "speaker": None,
        }
        session.finalized_segments.append(segment)
        persist_session(session)
        await publish(session, "transcript.segment.final", segment)
        if force:
            break


async def start_recording(session: Session) -> None:
    if session.recording:
        return
    session.audio_file = audio_path(session).open("ab")
    session.recording = True
    session.recording_started_at = time.monotonic()
    session.state = "recording"
    persist_session(session)
    await publish(session, "recording.started", {"path": audio_path(session).name})
    log_event("info", "recording.started", sessionId=session.id)


async def stop_recording(session: Session) -> None:
    if not session.recording:
        return
    if session.audio_file is not None:
        session.audio_file.flush()
        session.audio_file.close()
        session.audio_file = None
    session.recording = False
    if not session.transcribing:
        session.state = "completed"
    duration = time.monotonic() - (session.recording_started_at or time.monotonic())
    persist_session(session)
    await publish(session, "recording.finalized", {
        "path": audio_path(session).name,
        "duration": duration,
        "bytes": session.audio_bytes,
    })
    log_event("info", "recording.finalized", sessionId=session.id, durationSeconds=round(duration, 3), bytes=session.audio_bytes)


app = FastAPI(title="VoiceTranscribe Linux", version=APP_VERSION)

log_event("info", "service.started", version=APP_VERSION, build=APP_BUILD, asrEngine=ASR_ENGINE, logLevel=LOG_LEVEL)


def error_response(request: Request, status_code: int, code: str, message: str) -> JSONResponse:
    request_id = getattr(request.state, "request_id", None) or request.headers.get("X-Request-ID") or str(uuid.uuid4())
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message, "requestId": request_id}},
        headers={"X-Request-ID": request_id},
    )


@app.middleware("http")
async def security_headers(request: Request, call_next: Any) -> JSONResponse:
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "same-origin")
    response.headers.setdefault("Permissions-Policy", "microphone=(self)")
    return response


@app.middleware("http")
async def request_id_middleware(request: Request, call_next: Any) -> JSONResponse:
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    request.state.request_id = request_id
    path = request.url.path
    # API requests are operations-relevant; static asset traffic stays at debug.
    log_level = "info" if path.startswith("/api/") else "debug"
    started = time.perf_counter()

    def elapsed_ms() -> float:
        return round((time.perf_counter() - started) * 1000, 2)

    try:
        response = await call_next(request)
    except Exception:
        log_event(log_level, "http.request", requestId=request_id, method=request.method, path=path, status=500, durationMs=elapsed_ms())
        return error_response(request, 500, "internal_error", "An unexpected server error occurred")
    response.headers["X-Request-ID"] = request_id
    log_event(log_level, "http.request", requestId=request_id, method=request.method, path=path, status=response.status_code, durationMs=elapsed_ms())
    return response


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exception: HTTPException) -> JSONResponse:
    detail = exception.detail if isinstance(exception.detail, str) else "Request failed"
    code = "not_found" if exception.status_code == 404 else "request_failed"
    return error_response(request, exception.status_code, code, detail)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, _: RequestValidationError) -> JSONResponse:
    return error_response(request, 422, "validation_error", "Request validation failed")


@app.get("/api/metrics")
async def metrics() -> dict[str, Any]:
    queue_depth = sum(source.status in {"queued", "loading", "normalizing", "transcribing", "finalizing"} for source in file_sources.values())
    active_sessions = sum(session.recording or session.transcribing for session in sessions.values())
    storage_bytes = sum(path.stat().st_size for path in FILES_DIR.rglob("*") if path.is_file())
    return {
        "version": APP_VERSION,
        "build": APP_BUILD,
        "sessions": {"total": len(sessions), "active": active_sessions},
        "files": {"total": len(file_sources), "processing": queue_depth},
        "storage": {"bytes": storage_bytes},
        "asr": {"engine": ASR_ENGINE, "model": ASR_MODEL if ASR_ENGINE == "faster-whisper" else "demo"},
    }


@app.get("/api/diagnostics")
async def diagnostics() -> dict[str, Any]:
    current_metrics = await metrics()
    return {
        "diagnosticsVersion": 1,
        "application": {"version": APP_VERSION, "build": APP_BUILD},
        "runtime": {"asrEngine": ASR_ENGINE, "asrModel": ASR_MODEL if ASR_ENGINE == "faster-whisper" else "demo"},
        "metrics": current_metrics,
        "features": {"browserCapture": True, "fileImport": True, "playback": True, "diarization": False, "aiPrompts": False, "jev": False},
    }


@app.get("/api/health/live")
async def health_live() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/health/ready")
async def health_ready() -> dict[str, Any]:
    return {
        "status": "ready",
        "version": APP_VERSION,
        "build": APP_BUILD,
        "asrEngine": ASR_ENGINE,
        "asrModel": ASR_MODEL if ASR_ENGINE == "faster-whisper" else "demo",
        "asrAvailable": ASR_ENGINE == "fake" or faster_whisper_available(),
        "dataDirectory": str(DATA_DIR),
    }


@app.get("/api/capabilities")
async def capabilities() -> dict[str, Any]:
    return {
        "version": APP_VERSION,
        "build": APP_BUILD,
        "browserCapture": True,
        "hostCapture": False,
        "fileImport": True,
        "fileTranscription": True,
        "fakeASR": ASR_ENGINE == "fake",
        "localASR": ASR_ENGINE == "faster-whisper" and faster_whisper_available(),
        "asrEngine": ASR_ENGINE,
        "asrModel": ASR_MODEL if ASR_ENGINE == "faster-whisper" else "demo",
        "diarization": False,
        "aiPrompts": False,
        "jev": False,
        "markdownExport": True,
        "playback": True,
        "supportedFileFormats": sorted(SUPPORTED_EXTENSIONS),
    }


@app.post("/api/sessions", status_code=201)
async def create_session(request: SessionCreate) -> dict[str, Any]:
    session_id = str(uuid.uuid4())
    session = Session(
        id=session_id,
        source_name=request.source_name,
        sample_rate=request.sample_rate,
        channels=request.channels,
        created_at=now_iso(),
    )
    sessions[session_id] = session
    persist_session(session)
    await publish(session, "session.created", session.snapshot())
    log_event("info", "session.created", sessionId=session_id, sampleRate=session.sample_rate, channels=session.channels)
    return session.snapshot()


@app.post("/api/files", status_code=201)
async def upload_file(file: UploadFile = File(...)) -> dict[str, Any]:
    original_name = Path(file.filename or "upload").name
    extension = Path(original_name).suffix.lower().lstrip(".")
    if extension not in SUPPORTED_EXTENSIONS:
        log_event("warning", "file.upload.rejected", reason="unsupported_format", extension=extension)
        raise HTTPException(status_code=415, detail=f"Unsupported audio format: .{extension or 'unknown'}")
    file_id = str(uuid.uuid4())
    target = FILES_DIR / f"{file_id}-original.{extension}"
    size = 0
    try:
        with target.open("wb") as output:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="File exceeds the upload size limit")
                output.write(chunk)
    except HTTPException:
        target.unlink(missing_ok=True)
        log_event("warning", "file.upload.rejected", reason="upload_too_large", sizeBytes=size, limitBytes=MAX_UPLOAD_BYTES)
        raise
    duration, sample_rate, channels, codec = await asyncio.to_thread(probe_media, target)
    source = FileSource(
        id=file_id,
        original_name=original_name,
        original_path=target,
        normalized_path=None,
        size_bytes=size,
        duration=duration,
        sample_rate=sample_rate,
        channels=channels,
        format_name=codec or extension.upper(),
    )
    file_sources[file_id] = source
    persist_file_source(source)
    try:
        await normalize_media_async(source)
    except RuntimeError as error:
        source.status = "failed"
        source.error = str(error)
        persist_file_source(source)
        log_event("warning", "file.upload.rejected", reason="invalid_media", fileId=file_id, error=str(error))
        raise HTTPException(status_code=422, detail=source.error)
    log_event("info", "file.uploaded", fileId=file_id, sizeBytes=size, format=source.format_name, duration=source.duration)
    return source.snapshot()


@app.get("/api/files")
async def list_files() -> list[dict[str, Any]]:
    return [source.snapshot() for source in file_sources.values()]


@app.get("/api/files/{file_id}")
async def file_snapshot(file_id: str) -> dict[str, Any]:
    source = file_sources.get(file_id)
    if source is None:
        raise HTTPException(status_code=404, detail="File source not found")
    return source.snapshot()


@app.get("/api/files/{file_id}/audio")
async def file_audio(file_id: str) -> FileResponse:
    source = file_sources.get(file_id)
    if source is None:
        raise HTTPException(status_code=404, detail="File source not found")
    if not source.original_path.exists():
        raise HTTPException(status_code=404, detail="Original audio artifact is unavailable")
    media_type = mimetypes.guess_type(source.original_name)[0] or "application/octet-stream"
    return FileResponse(source.original_path, media_type=media_type, filename=source.original_name)


@app.delete("/api/files/{file_id}")
async def delete_file(file_id: str) -> dict[str, Any]:
    source = file_sources.get(file_id)
    if source is None:
        raise HTTPException(status_code=404, detail="File source not found")
    if source.status in {"normalizing", "transcribing"}:
        raise HTTPException(status_code=409, detail="Cannot delete a file while it is processing")
    linked_session = sessions.get(source.session_id) if source.session_id else None
    if linked_session is not None and (linked_session.recording or linked_session.transcribing):
        raise HTTPException(status_code=409, detail="Cannot delete a file with an active transcription session")
    remove_artifact(source.original_path)
    remove_artifact(source.normalized_path)
    if linked_session is not None:
        delete_session_data(linked_session)
    with sqlite3.connect(DB_PATH) as database:
        database.execute("DELETE FROM file_sources WHERE id = ?", (file_id,))
    file_sources.pop(file_id, None)
    return {"deleted": True, "fileId": file_id}


@app.post("/api/files/{file_id}/transcribe", status_code=202)
async def file_transcribe(file_id: str) -> dict[str, Any]:
    source = file_sources.get(file_id)
    if source is None:
        raise HTTPException(status_code=404, detail="File source not found")
    if source.status not in {"ready", "failed"}:
        raise HTTPException(status_code=409, detail="File is already processing or has completed transcription")
    if source.normalized_path is None or not source.normalized_path.exists():
        raise HTTPException(status_code=422, detail="File has no normalized audio artifact")
    if source.status == "failed" and source.session_id:
        previous_session = sessions.get(source.session_id)
        if previous_session is not None:
            delete_session_data(previous_session)
        source.session_id = None
    source.status = "queued"
    source.progress = 0.0
    source.error = None
    source.job_id = str(uuid.uuid4())
    persist_file_source(source)
    log_event("info", "file.job.queued", jobId=source.job_id, fileId=source.id)
    asyncio.create_task(transcribe_file(source))
    return source.snapshot()


@app.get("/api/sessions")
async def list_sessions() -> list[dict[str, Any]]:
    return [session.snapshot() for session in sessions.values()]


@app.get("/api/sessions/{session_id}")
async def session_snapshot(session_id: str) -> dict[str, Any]:
    return get_session(session_id).snapshot()


@app.post("/api/sessions/{session_id}/recording/start")
async def recording_start(session_id: str, _: SessionCommand | None = None) -> dict[str, Any]:
    session = get_session(session_id)
    await start_recording(session)
    return session.snapshot()


@app.post("/api/sessions/{session_id}/recording/stop")
async def recording_stop(session_id: str, _: SessionCommand | None = None) -> dict[str, Any]:
    session = get_session(session_id)
    await stop_recording(session)
    return session.snapshot()


@app.post("/api/sessions/{session_id}/transcription/start")
async def transcription_start(session_id: str, _: SessionCommand | None = None) -> dict[str, Any]:
    session = get_session(session_id)
    session.transcribing = True
    session.paused = False
    session.asr_status = "waiting"
    session.asr_last_error = None
    session.state = "recording" if session.recording else "transcribing"
    persist_session(session)
    await publish(session, "transcription.started", {"engine": ASR_ENGINE, "model": ASR_MODEL if ASR_ENGINE == "faster-whisper" else "demo"})
    log_event("info", "transcription.started", sessionId=session_id, engine=ASR_ENGINE)
    return session.snapshot()


@app.post("/api/sessions/{session_id}/transcription/pause")
async def transcription_pause(session_id: str, _: SessionCommand | None = None) -> dict[str, Any]:
    session = get_session(session_id)
    if session.transcribing:
        session.paused = True
        persist_session(session)
        await publish(session, "transcription.paused", {})
        log_event("info", "transcription.paused", sessionId=session_id)
    return session.snapshot()


@app.post("/api/sessions/{session_id}/transcription/resume")
async def transcription_resume(session_id: str, _: SessionCommand | None = None) -> dict[str, Any]:
    session = get_session(session_id)
    if session.transcribing:
        session.paused = False
        persist_session(session)
        await publish(session, "transcription.resumed", {})
        log_event("info", "transcription.resumed", sessionId=session_id)
    return session.snapshot()


@app.post("/api/sessions/{session_id}/transcription/stop")
async def transcription_stop(session_id: str, _: SessionCommand | None = None) -> dict[str, Any]:
    session = get_session(session_id)
    if ASR_ENGINE == "faster-whisper":
        await drain_live_asr(session)
    else:
        await fake_finalize(session, force=True)
    session.transcribing = False
    session.paused = False
    session.asr_status = "idle"
    session.state = "recording" if session.recording else "completed"
    persist_session(session)
    await publish(session, "transcription.completed", {"segments": len(session.finalized_segments)})
    log_event("info", "transcription.stopped", sessionId=session_id, segments=len(session.finalized_segments))
    return session.snapshot()


@app.delete("/api/sessions/{session_id}")
async def delete_session(session_id: str) -> dict[str, Any]:
    session = get_session(session_id)
    if session.recording or session.transcribing or (session.live_asr_task is not None and not session.live_asr_task.done()):
        raise HTTPException(status_code=409, detail="Stop recording and transcription before deleting the session")
    for source in list(file_sources.values()):
        if source.session_id == session_id:
            remove_artifact(source.original_path)
            remove_artifact(source.normalized_path)
            with sqlite3.connect(DB_PATH) as database:
                database.execute("DELETE FROM file_sources WHERE id = ?", (source.id,))
            file_sources.pop(source.id, None)
    delete_session_data(session)
    log_event("info", "session.deleted", sessionId=session_id)
    return {"deleted": True, "sessionId": session_id}


@app.get("/api/sessions/{session_id}/export/markdown")
async def export_markdown(session_id: str) -> JSONResponse:
    session = get_session(session_id)
    content = markdown_for(session)
    return JSONResponse(
        content={"filename": f"{session.id}.md", "content": content},
        headers={"Content-Disposition": f'attachment; filename="{session.id}.json"'},
    )


@app.websocket("/api/sessions/{session_id}/events")
async def events_socket(websocket: WebSocket, session_id: str, after: int = Query(default=0, ge=0)) -> None:
    session = sessions.get(session_id)
    if session is None:
        await websocket.close(code=4404, reason="Session not found")
        return
    await websocket.accept()
    async with session.lock:
        session.clients.add(websocket)
        client_count = len(session.clients)
        replay = [event for event in session.events if event["sequence"] > after]
    log_event("info", "ws.connected", sessionId=session_id, clients=client_count)
    for event in replay:
        await websocket.send_json(event)
    pending_audio_frame: dict[str, Any] | None = None
    try:
        while True:
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                break
            if message.get("bytes") is not None:
                audio = message["bytes"]
                frame = pending_audio_frame or {}
                pending_audio_frame = None
                if session.recording and session.audio_file is not None:
                    session.audio_file.write(audio)
                session.audio_bytes += len(audio)
                if ASR_ENGINE == "faster-whisper" and session.transcribing:
                    if session.paused:
                        # Recording keeps the bytes, but paused audio is deliberately not sent to ASR.
                        session.live_asr_bytes += len(audio)
                    else:
                        session.live_pcm.extend(audio)
                        await schedule_live_asr(session)
                else:
                    await fake_finalize(session)
                await websocket.send_json({
                    "type": "audio.ack",
                    "sessionId": session.id,
                    "sequence": session.next_sequence - 1,
                    "occurredAt": now_iso(),
                    "payload": {
                        "bytes": len(audio),
                        "totalBytes": session.audio_bytes,
                        "frameSequence": frame.get("frameSequence"),
                        "capturedAt": frame.get("capturedAt"),
                    },
                })
            elif message.get("text"):
                try:
                    command = json.loads(message["text"])
                except json.JSONDecodeError:
                    continue
                if command.get("type") == "client.audio.frame":
                    pending_audio_frame = {
                        "frameSequence": int(command.get("frameSequence", 0)),
                        "capturedAt": command.get("capturedAt"),
                    }
                elif command.get("type") == "client.level":
                    await publish(session, "audio.level", {
                        "rms": float(command.get("rms", 0)),
                        "peak": float(command.get("peak", 0)),
                        "clipping": bool(command.get("clipping", False)),
                    })
    except WebSocketDisconnect:
        pass
    finally:
        async with session.lock:
            session.clients.discard(websocket)
            remaining_clients = len(session.clients)
        log_event("info", "ws.disconnected", sessionId=session_id, clients=remaining_clients)


@app.get("/api/sessions/{session_id}/audio")
async def audio_file(session_id: str) -> FileResponse:
    session = get_session(session_id)
    path = audio_path(session)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Audio is not finalized")
    return FileResponse(path, media_type="application/octet-stream", filename=path.name)


app.mount("/", StaticFiles(directory=STATIC_DIR, html=True), name="static")
