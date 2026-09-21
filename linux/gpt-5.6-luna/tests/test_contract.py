import os
from pathlib import Path

os.environ["VT_DATA_DIR"] = str(Path(__file__).parent / "data")

from fastapi.testclient import TestClient

from app.main import APP_BUILD, APP_VERSION, Session, app, load_persistent_state, markdown_for, persist_session, sessions


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
