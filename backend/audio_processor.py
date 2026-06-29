import os
import whisper

def convert_audio_locally(audio_file_path: str) -> str:
    print("Loading local Whisper AI Model (Base size)...")
    model = whisper.load_model("base")
    
    print(f"Transcribing: {audio_file_path}...")
    # Added fp16=False to prevent unnecessary CPU warnings on Windows machines
    result = model.transcribe(audio_file_path, fp16=False) 
    raw_transcript = str(result["text"])
    
    print("\n--- RAW TRANSCRIPT GENERATED ---")
    print(raw_transcript)
    
    # --- SAVE TO TXT FILE LOGIC ---
    base_name = os.path.splitext(os.path.basename(audio_file_path))[0]
    output_dir = "transcripts"
    os.makedirs(output_dir, exist_ok=True)
    output_file_path = os.path.join(output_dir, f"{base_name}.txt")
    
    print(f"Saving transcript to: {output_file_path}...")
    with open(output_file_path, "w", encoding="utf-8") as file:
        file.write(str(raw_transcript))
        
    print("File saved successfully!")
    
    return raw_transcript

# THIS PREVENTS AUTOMATIC RUNNING ON IMPORT:
if __name__ == "__main__":
    # This will only execute if you run 'python audio_processor.py' directly
    convert_audio_locally("audio/scenario1.mp3")