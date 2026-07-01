"""
pipeline.py — core audio-to-job processing logic.

Can be called by:
  - api.py       (FastAPI endpoint — accepts uploaded file)
  - main.py      (CLI — reads from the local audio/ folder)
"""

import os
from supabase import Client
from transcript_processor import process_transcript_with_langchain
from audio_processor import convert_audio_locally


def run_pipeline(audio_path: str, supabase: Client) -> dict:
    """
    Full pipeline: audio file → Whisper → LLM → Supabase insert.

    Args:
        audio_path: Absolute or relative path to the audio file on disk.
        supabase:   An initialised Supabase client.

    Returns:
        A dict with one of two shapes:
          {"status": "created",   "job": { ...job fields... }}
          {"status": "duplicate", "message": "..."}

    Raises:
        ValueError: if the transcript is empty.
        Exception:  propagates any Supabase or LLM errors to the caller.
    """

    # ── Step 1: Transcript (use cached .txt if available) ──────────────────
    base_name        = os.path.splitext(os.path.basename(audio_path))[0]
    transcript_dir   = os.path.join(os.path.dirname(audio_path), "..", "transcripts")
    transcript_dir   = os.path.normpath(transcript_dir)
    transcript_path  = os.path.join(transcript_dir, f"{base_name}.txt")

    if os.path.exists(transcript_path):
        print(f"⏩ Using cached transcript: {transcript_path}")
        with open(transcript_path, "r", encoding="utf-8") as f:
            file_content = f.read()
    else:
        print("🎙️  Running Whisper transcription…")
        file_content = convert_audio_locally(audio_path)

        if not file_content.strip():
            raise ValueError("Whisper produced an empty transcript.")

        os.makedirs(transcript_dir, exist_ok=True)
        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(file_content)
        print(f"💾 Transcript cached to {transcript_path}")

    # ── Step 2: LLM structuring ────────────────────────────────────────────
    print("🧠 Running LLM structuring pipeline…")
    structured = process_transcript_with_langchain(file_content)

    phone   = structured["phone"]
    address = structured["address"]

    # ── Step 3: Duplicate guard ────────────────────────────────────────────
    existing = (
        supabase.table("jobs")
        .select("id", count="exact")
        .eq("phone", phone)
        .eq("address", address)
        .neq("status", "Complete")
        .execute()
    )

    if existing.count and existing.count > 0:
        msg = (
            f"Duplicate skipped: open job already exists for "
            f"'{phone}' at '{address}'."
        )
        print(f"⚠️  {msg}")
        return {"status": "duplicate", "message": msg}

    # ── Step 4: Insert into Supabase ───────────────────────────────────────
    job_data = {
        "name":     structured["name"],
        "phone":    phone,
        "address":  address,
        "summary":  structured["summary"],
        "priority": structured["priority"],
        "status":   "Pending",
    }

    response = supabase.table("jobs").insert(job_data).execute()
    created_job = response.data[0] if response.data else job_data

    print("✅ Job inserted into Supabase.")
    return {"status": "created", "job": created_job}
