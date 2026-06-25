import os
from dotenv import load_dotenv 
from transcript_processor import process_transcript_with_langchain
# IMPORT YOUR AUDIO FUNCTION HERE:
# (Change 'audio_processor' to match whatever your actual audio file name is)
from audio_processor import convert_audio_locally 

# Load environment variables from the .env file right away
load_dotenv()

def main():
    # Define the target audio file path
    audio_path = os.path.join("audio", "scenario1.mp3")
    
    # Verification Guard: Make sure the audio file actually exists before starting
    if not os.path.exists(audio_path):
        print(f"Error: The audio file '{audio_path}' was not found.")
        print("Please ensure your audio file is placed inside the 'audio' folder!")
        return

    # 1. AUDIO-TO-TEXT (Imported from your dedicated file)
    print("1. Starting Audio to Text Pipeline...")
    file_content = convert_audio_locally(audio_path)
    
    if not file_content.strip():
        print("Error: Generated transcript is completely empty.")
        return

    # 2 & 3. PROMPT STRUCTURING & WATSONX GENERATION
    print("\n2. Initializing LangChain and IBM Watsonx pipeline...")
    print("3. Packaging text into the template and running through LLM...")
    
    final_output = process_transcript_with_langchain(file_content)
    
    # 4. Display output results
    print("\n--- FINAL STRUCTURED DATA CARD ---")
    print(final_output)
    print(f"Data type confirmed: {type(final_output)}")

if __name__ == "__main__":
    main()