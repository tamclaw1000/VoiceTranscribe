import json
import os
from pathlib import Path

os.environ["VT_DATA_DIR"] = str(Path(__file__).parent / "data")

from fastapi.testclient import TestClient

from app.main import APP_BUILD, APP_VERSION, FileSource, Session, app, audio_path, load_persistent_state, markdown_for, persist_session, sessions


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
        websocket.close()

    assert not sessions[session_id].clients
    with client.websocket_connect(f"/api/sessions/{session_id}/events?after={created_event['sequence']}") as websocket:
        replayed_event = websocket.receive_json()
        assert replayed_event["sequence"] == level_event["sequence"]
        assert replayed_event["type"] == "audio.level"

    sessions.pop(session_id, None)


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
