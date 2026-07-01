"""
api.py — FastAPI server for the Audio Analyzer backend.

Run with:
    uvicorn api:app --host 0.0.0.0 --port 8000 --reload

Endpoints:
    GET  /health          → health check
    POST /process-audio   → upload an audio file, get back a structured job
"""

import os
import shutil
import tempfile

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client

from pipeline import run_pipeline

# ── Startup ────────────────────────────────────────────────────────────────

load_dotenv()

SUPABASE_URL: str = os.environ["SUPABASE_URL"]
SUPABASE_KEY: str = os.environ["SUPABASE_KEY"]

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

app = FastAPI(
    title="Audio Analyzer API",
    description="Transcribes audio dispatches and creates structured jobs in Supabase.",
    version="1.0.0",
)

# Allow requests from the Flutter web build and local development tools
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routes ─────────────────────────────────────────────────────────────────

@app.get("/health", tags=["System"])
def health_check():
    """Quick liveness check — returns 200 if the server is running."""
    return {"status": "ok", "service": "Audio Analyzer API"}


@app.post("/process-audio", tags=["Jobs"])
async def process_audio(file: UploadFile = File(...)):
    """
    Accept an audio file upload, run the full pipeline, and return the result.

    - Saves the upload to a temp file on disk
    - Runs Whisper transcription (skips if a cached transcript exists)
    - Runs the LLM structuring pipeline
    - Inserts a new job into Supabase (with duplicate guard)
    - Returns the created job data or a duplicate notice

    Supported formats: .mp3, .wav, .m4a, .ogg, .flac
    """
    allowed_extensions = {".mp3", ".wav", ".m4a", ".ogg", ".flac"}
    _, ext = os.path.splitext(file.filename or "")

    if ext.lower() not in allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{ext}'. Allowed: {', '.join(allowed_extensions)}",
        )

    # Write upload to a named temp file so Whisper can read it from disk
    with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = tmp.name

    try:
        result = run_pipeline(audio_path=tmp_path, supabase=supabase)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Pipeline error: {e}")
    finally:
        os.unlink(tmp_path)  # always clean up the temp file

    if result["status"] == "duplicate":
        raise HTTPException(status_code=409, detail=result["message"])

    return result  # {"status": "created", "job": {...}}
