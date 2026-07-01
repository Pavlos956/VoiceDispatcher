"""
main.py — CLI entry point for the Audio Analyzer backend.

Use this to manually process a single audio file from the local audio/ folder.
For the live API server, run api.py instead:
    uvicorn api:app --host 0.0.0.0 --port 8000 --reload
"""

import os
from dotenv import load_dotenv
from supabase import create_client, Client
from pipeline import run_pipeline

load_dotenv()

SUPABASE_URL: str = os.environ["SUPABASE_URL"]
SUPABASE_KEY: str = os.environ["SUPABASE_KEY"]

if not SUPABASE_URL or not SUPABASE_KEY:
    print("Error: Supabase credentials missing from .env file!")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


def main():
    audio_filename = "scenario3.mp3"
    audio_path = os.path.join("audio", audio_filename)

    if not os.path.exists(audio_path):
        # Check if a cached transcript exists even without the audio file
        base_name       = os.path.splitext(audio_filename)[0]
        transcript_path = os.path.join("transcripts", f"{base_name}.txt")
        if not os.path.exists(transcript_path):
            print(f"Error: '{audio_path}' not found and no cached transcript exists.")
            return

    print(f"▶️  Processing: {audio_filename}")
    result = run_pipeline(audio_path=audio_path, supabase=supabase)

    if result["status"] == "duplicate":
        print(f"⚠️  {result['message']}")
    else:
        print("\n--- CREATED JOB ---")
        print(result["job"])
        print("✅ Done.")


if __name__ == "__main__":
    main()
