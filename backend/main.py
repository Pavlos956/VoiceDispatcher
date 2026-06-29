import os
from dotenv import load_dotenv 
from supabase import create_client, Client
from transcript_processor import process_transcript_with_langchain
from audio_processor import convert_audio_locally 

# Load environment variables from the .env file right away
load_dotenv()

SUPABASE_URL: str = os.environ["SUPABASE_URL"]
SUPABASE_KEY: str = os.environ["SUPABASE_KEY"]

if not SUPABASE_URL or not SUPABASE_KEY:
    print("Error: Supabase credentials missing from .env file!")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


def main():
    # 1. Define paths for both the audio and the cached transcript text file
    audio_filename = "scenario2.mp3"
    base_name, extension = os.path.splitext(audio_filename)
    transcript_filename = f"{base_name}.txt"
    
    audio_path = os.path.join("audio", audio_filename)
    transcript_dir = "transcripts"
    transcript_path = os.path.join(transcript_dir, transcript_filename)
    
    file_content = ""

    # 2. Optimization Check: Does the text transcript already exist?
    if os.path.exists(transcript_path):
        print(f"⏩ Found existing transcript file at '{transcript_path}'. Skipping Whisper transcription!")
        print("Reading transcript from disk...")
        with open(transcript_path, "r", encoding="utf-8") as f:
            file_content = f.read()
            
    else:
        # If it doesn't exist, we must have the audio file to generate it
        if not os.path.exists(audio_path):
            print(f"Error: The audio file '{audio_path}' was not found.")
            print("Please ensure your audio file is placed inside the 'audio' folder!")
            return

        # Phase 1: AUDIO-TO-TEXT (Run Whisper)
        print("1. Starting Audio to Text Pipeline via Whisper...")
        file_content = convert_audio_locally(audio_path)
        
        if not file_content.strip():
            print("Error: Generated transcript is completely empty.")
            return
        
        # Save the freshly generated transcript to disk so we can skip it next time
        os.makedirs(transcript_dir, exist_ok=True) # Ensures the transcripts directory exists
        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(file_content)
        print(f"💾 Saved transcript locally to '{transcript_path}' for future caching.")

    # Phase 2 & 3: PROMPT STRUCTURING & WATSONX GENERATION
    print("\n2. Initializing LangChain and IBM Watsonx pipeline...")
    print("3. Packaging text into the template and running through LLM...")
    
    final_output = process_transcript_with_langchain(file_content)
    
    # 4. Display local results
    print("\n--- FINAL STRUCTURED DATA CARD ---")
    print(final_output)

    # Phase 4: PUSH TO CLOUD POSTGRESQL DATABASE
    print("\n4. Shipping structured data card to Supabase cloud database...")
    try:
        response = supabase.table("jobs").insert({
            "name":      final_output["name"],
            "phone":     final_output["phone"],
            "address":   final_output["address"],
            "summary":   final_output["summary"],
            "priority":  final_output["priority"],
            "status":    "Pending" 
        }).execute()
        
        print("SUCCESS: Job data pushed seamlessly to your cloud database!")

    except Exception as e:
        print(f"DATABASE ERROR: Failed to push data to Supabase. Details: {e}")


if __name__ == "__main__":
    main()