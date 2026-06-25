import os
from transcript_processor import process_transcript_with_langchain
from dotenv import load_dotenv 

# Load environment variables from the .env file right away
load_dotenv()

def main():
    # Define the path to your transcript file
    transcript_path = os.path.join("transcripts", "scenario1.txt")
    
    # 1. Verification Guard: Make sure the file actually exists before processing
    if not os.path.exists(transcript_path):
        print(f"Error: The file '{transcript_path}' was not found.")
        print("Please ensure your Whisper script ran successfully first!")
        return

    # 2. Read the text file safely using UTF-8 encoding
    print(f"Reading file directly from: {transcript_path}")
    with open(transcript_path, "r", encoding="utf-8") as file:
        file_content = file.read()
        
    if not file_content.strip():
        print(f"Warning: '{transcript_path}' is completely empty.")
        return

    # 3. Pass the file content right into your LangChain module
    final_output = process_transcript_with_langchain(file_content)
    
    # 4. Display output results
    print("\n--- FINAL STRUCTURED DATA CARD ---")
    print(final_output)
    print(f"Data type confirmed: {type(final_output)}")

if __name__ == "__main__":
    main()