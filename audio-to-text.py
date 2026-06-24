import whisper

def convert_audio_locally(audio_file_path: str):
    print("Loading local Whisper AI Model (Base size)...")
    # This downloads the model once to your computer. 'base' balances speed and accuracy perfectly.
    model = whisper.load_model("base")
    
    print(f"Transcribing: {audio_file_path}...")
    # Whisper automatically handles format conversions and returns a dictionary
    result = model.transcribe(audio_file_path)
    
    raw_transcript = result["text"]
    
    print("\n--- RAW TRANSCRIPT GENERATED ---")
    print(raw_transcript)
    return raw_transcript

convert_audio_locally("audio/scenario1.mp3")