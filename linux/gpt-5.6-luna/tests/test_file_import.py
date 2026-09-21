import os
import struct
import wave
from pathlib import Path

os.environ["VT_DATA_DIR"] = str(Path(__file__).parent / "data-files")

from fastapi.testclient import TestClient

from app.main import FileSource, app, normalize_media, probe_media, write_float32_wav


def make_wav(path: Path) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(8000)
        output.writeframes(b"".join(struct.pack("<h", 0) for _ in range(800)))


def test_probe_and_normalize_wav(tmp_path):
    original = tmp_path / "sample.wav"
    make_wav(original)
    source = FileSource(
        id="file-1",
        original_name="sample.wav",
        original_path=original,
        normalized_path=None,
        size_bytes=original.stat().st_size,
        duration=None,
        sample_rate=None,
        channels=None,
        format_name="WAV",
    )
    duration, sample_rate, channels, _ = probe_media(original)
    assert duration is not None
    assert sample_rate == 8000
    assert channels == 1
    source.duration = duration
    source.sample_rate = sample_rate
    source.channels = channels
    normalize_media(source)
    assert source.normalized_path is not None
    assert source.normalized_path.exists()
    normalized_duration, normalized_rate, normalized_channels, _ = probe_media(source.normalized_path)
    assert normalized_duration is not None
    assert normalized_rate == 16000
    assert normalized_channels == 1


def test_write_float32_wav_creates_asr_compatible_pcm(tmp_path):
    path = tmp_path / "float.wav"
    samples = struct.pack("<4f", 0.0, 0.25, -0.25, 0.0)
    write_float32_wav(path, samples, 16000, 1)
    duration, sample_rate, channels, codec = probe_media(path)
    assert duration is not None
    assert sample_rate == 16000
    assert channels == 1
    assert codec == "pcm_s16le"


def test_upload_endpoint_creates_normalized_file_source(tmp_path):
    original = tmp_path / "upload.wav"
    make_wav(original)
    with original.open("rb") as stream:
        response = TestClient(app).post(
            "/api/files",
            files={"file": ("upload.wav", stream, "audio/wav")},
        )
    assert response.status_code == 201
    payload = response.json()
    assert payload["status"] == "ready"
    assert payload["sampleRate"] == 8000
    assert payload["id"]
    assert payload["audioUrl"] == f"/api/files/{payload['id']}/audio"
    assert payload["duration"] is not None
    audio_response = TestClient(app).get(payload["audioUrl"])
    assert audio_response.status_code == 200
    assert audio_response.headers["content-type"] in {"audio/wav", "audio/x-wav"}
