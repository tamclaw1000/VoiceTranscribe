import json
import os
from pathlib import Path

os.environ["VT_DATA_DIR"] = str(Path(__file__).parent / "data")

from fastapi.testclient import TestClient

from app.main import APP_BUILD, APP_VERSION, FileSource, Session, app, audio_path, file_sources, load_persistent_state, markdown_for, persist_session, sessions


def test_browser_shell_exposes_accessible_notification_surface():
    response = TestClient(app).get("/")
    assert response.status_code == 200
    assert 'id="notification"' in response.text
    assert 'role="status"' in response.text
    assert 'aria-live="polite"' in response.text
    assert 'id="deviceDetails"' in response.text
    assert 'id="captureFormat"' in response.text
    assert 'id="audioTransportLatency"' in response.text
    browser_script = (Path(__file__).parents[1] / "app" / "static" / "app.js").read_text()
    assert "waitForAudioFlush" in browser_script
    assert "lastAckedAudioFrame" in browser_script
    assert "visibilitychange" in browser_script
    assert "Tab inactive; capture may be delayed" in browser_script
    assert "audioTransportLatency" in browser_script


def test_health_and_capabilities_expose_version_and_build():
    client = TestClient(app)
    health = client.get("/api/health/ready")
    capabilities = client.get("/api/capabilities")
    assert health.json()["version"] == APP_VERSION
    assert health.json()["build"] == APP_BUILD
    assert capabilities.json()["version"] == APP_VERSION
    assert capabilities.json()["build"] == APP_BUILD


def test_completed_session_metadata_survives_state_reload():
    session = Session(
        id="persistent-session",
        source_name="Saved microphone",
        sample_rate=16000,
        channels=1,
        created_at="2026-09-21T00:00:00+00:00",
        state="completed",
        finalized_segments=[{"segmentId": "segment-1", "text": "Saved.", "audioOffset": 0.0}],
    )
    persist_session(session)
    sessions.pop(session.id, None)
    load_persistent_state()
    assert sessions[session.id].source_name == "Saved microphone"
    assert sessions[session.id].finalized_segments[0]["text"] == "Saved."


def test_markdown_export_contains_transcript_and_audio_reference():
    session = Session(
        id="session-1",
        source_name="Test microphone",
        sample_rate=16_000,
        channels=1,
        created_at="2026-09-21T00:00:00+00:00",
        state="completed",
        finalized_segments=[
            {
                "segmentId": "segment-1",
                "sentenceIndex": 0,
                "text": "A test sentence.",
                "audioOffset": 5.0,
                "isFinal": True,
                "speaker": None,
            }
        ],
    )
    output = markdown_for(session)
    assert "# RECORDING" in output
    assert "A test sentence." in output
    assert "session-1.pcm" in output


def test_api_errors_have_stable_envelope_and_request_id():
    client = TestClient(app)
    response = client.get("/api/sessions/does-not-exist")
    body = response.json()
    assert response.status_code == 404
    assert body["error"]["code"] == "not_found"
    assert body["error"]["message"] == "Session not found"
    assert body["error"]["requestId"] == response.headers["X-Request-ID"]

    supplied = client.get("/api/sessions/does-not-exist", headers={"X-Request-ID": "request-test-1"})
    assert supplied.headers["X-Request-ID"] == "request-test-1"
    assert supplied.json()["error"]["requestId"] == "request-test-1"


def test_validation_errors_use_stable_envelope():
    client = TestClient(app)
    response = client.post("/api/sessions", json={"sample_rate": 1})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert response.json()["error"]["requestId"] == response.headers["X-Request-ID"]


def test_file_snapshot_exposes_linked_transcript():
    session = Session(
        id="file-session",
        source_name="speech.wav",
        sample_rate=16000,
        channels=1,
        created_at="2026-09-21T00:00:00+00:00",
        state="completed",
        finalized_segments=[{"segmentId": "segment-1", "text": "Recognized text.", "audioOffset": 0.0}],
    )
    sessions[session.id] = session
    source = FileSource(
        id="file-source",
        original_name="speech.wav",
        original_path=Path("/data/files/file-source-original.wav"),
        normalized_path=None,
        size_bytes=10,
        duration=1.0,
        sample_rate=16000,
        channels=1,
        format_name="WAV",
        status="completed",
        progress=1.0,
        session_id=session.id,
    )
    assert source.snapshot()["transcript"][0]["text"] == "Recognized text."
    sessions.pop(session.id, None)


def test_websocket_reconnect_replays_events_and_cleans_up_disconnect():
    client = TestClient(app)
    created = client.post("/api/sessions", json={"source_name": "WebSocket test"}).json()
    session_id = created["sessionId"]

    with client.websocket_connect(f"/api/sessions/{session_id}/events?after=0") as websocket:
        created_event = websocket.receive_json()
        assert created_event["type"] == "session.created"
        websocket.send_text(json.dumps({"type": "client.level", "rms": 0.25, "peak": 0.5}))
        level_event = websocket.receive_json()
        assert level_event["type"] == "audio.level"
        assert level_event["payload"]["peak"] == 0.5
        websocket.send_text(json.dumps({"type": "client.audio.frame", "frameSequence": 7, "capturedAt": 1726920000000}))
        websocket.send_bytes(b"\x00\x00\x00\x00")
        audio_ack = websocket.receive_json()
        assert audio_ack["type"] == "audio.ack"
        assert audio_ack["payload"]["frameSequence"] == 7
        assert audio_ack["payload"]["capturedAt"] == 1726920000000
        websocket.close()

    assert not sessions[session_id].clients
    with client.websocket_connect(f"/api/sessions/{session_id}/events?after={created_event['sequence']}") as websocket:
        replayed_event = websocket.receive_json()
        assert replayed_event["sequence"] == level_event["sequence"]
        assert replayed_event["type"] == "audio.level"

    sessions.pop(session_id, None)


def test_failed_file_transcription_can_be_requeued(tmp_path):
    original = tmp_path / "retry.wav"
    normalized = tmp_path / "retry-normalized.wav"
    original.write_bytes(b"original")
    normalized.write_bytes(b"normalized")
    previous = Session(
        id="failed-file-session",
        source_name="retry.wav",
        sample_rate=16000,
        channels=1,
        created_at="2026-09-21T00:00:00+00:00",
        state="failed",
    )
    sessions[previous.id] = previous
    source = FileSource(
        id="retry-file",
        original_name="retry.wav",
        original_path=original,
        normalized_path=normalized,
        size_bytes=10,
        duration=0.0,
        sample_rate=16000,
        channels=1,
        format_name="WAV",
        status="failed",
        error="Temporary ASR failure",
        session_id=previous.id,
    )
    file_sources[source.id] = source
    response = TestClient(app).post(f"/api/files/{source.id}/transcribe")
    assert response.status_code == 202
    assert response.json()["status"] == "queued"
    assert response.json()["error"] is None
    file_sources.pop(source.id, None)
    for session_id, candidate in list(sessions.items()):
        if candidate.source_name == "retry.wav":
            sessions.pop(session_id, None)
    sessions.pop(previous.id, None)


def test_session_delete_removes_recording_artifact_and_metadata():
    client = TestClient(app)
    created = client.post("/api/sessions", json={"source_name": "Delete me"}).json()
    session_id = created["sessionId"]
    artifact = audio_path(sessions[session_id])
    artifact.write_bytes(b"pcm")
    response = client.delete(f"/api/sessions/{session_id}")
    assert response.status_code == 200
    assert response.json() == {"deleted": True, "sessionId": session_id}
    assert session_id not in sessions
    assert not artifact.exists()


def test_session_snapshot_keeps_recording_and_transcription_independent():
    session = Session(
        id="session-2",
        source_name="Browser microphone",
        sample_rate=48_000,
        channels=1,
        created_at="2026-09-21T00:00:00+00:00",
        recording=True,
        transcribing=True,
    )
    snapshot = session.snapshot()
    assert snapshot["recording"] is True
    assert snapshot["transcribing"] is True
    assert snapshot["state"] == "created"
    assert snapshot["asrStatus"] == "idle"
    assert snapshot["asrWindowsProcessed"] == 0
