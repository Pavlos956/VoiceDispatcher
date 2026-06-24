import os
import whisper

def convert_audio_locally(audio_file_path: str) -> str:
    print("Loading local Whisper AI Model (Base size)...")
    model = whisper.load_model("base")
    
    print(f"Transcribing: {audio_file_path}...")
    result = model.transcribe(audio_file_path)
    raw_transcript = str(result["text"])
    
    print("\n--- RAW TRANSCRIPT GENERATED ---")
    print(raw_transcript)
    
    # --- SAVE TO TXT FILE LOGIC ---
    # 1. Extract the file name (e.g., 'scenario1') without 'audio/' or '.mp3'
    base_name = os.path.splitext(os.path.basename(audio_file_path))[0]
    
    # 2. Ensure the 'transcripts' directory exists
    output_dir = "transcripts"
    os.makedirs(output_dir, exist_ok=True)
    
    # 3. Create the destination file path (transcripts/scenario1.txt)
    output_file_path = os.path.join(output_dir, f"{base_name}.txt")
    
    # 4. Write the transcript text securely using UTF-8 encoding
    print(f"Saving transcript to: {output_file_path}...")
    with open(output_file_path, "w", encoding="utf-8") as file:
        file.write(str(raw_transcript))
        
    print("File saved successfully!")
    # -------------------------------
    
    return raw_transcript

# Run the updated function
convert_audio_locally("audio/scenario1.mp3")