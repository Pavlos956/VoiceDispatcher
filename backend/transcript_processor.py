import os
from langchain_core.prompts import PromptTemplate
from langchain_core.output_parsers import JsonOutputParser
from langchain_ibm import WatsonxLLM

def process_transcript_with_langchain(raw_transcript: str) -> dict:
    print("Initializing LangChain and IBM Granite pipeline...")
    
    # 1. Define the Master Prompt Template
    prompt_template = PromptTemplate.from_template(
        """You are an expert emergency dispatch assistant for a service company based in Cyprus. 
        Analyze the following phone transcript. Extract the key details and return them strictly as a valid JSON object.
        
        ### BUSINESS LOGIC RULES:
        1. PRIORITY ASSESSMENT:
           - Set "priority" to "Emergency" if there is active, uncontained property damage or hazard.
           - Set "priority" to "Standard" for routine inquiries or maintenance.
        
        2. CYPRUS GEOGRAPHY & SURNAME CLEANUP:
           - Automatically correct obvious phonetic transcriptions of Cyprus locations or Greek/Cypriot names into their correct proper spelling.
           - Example: "Lemusole" or "Limasol" must be corrected to "Limassol". 
           - Example: "Maria Papa Dopoloo" or "Papadopolou" must be properly formatted to "Maria Papadopoulou".
           - Example: "Macarios Avenue" should be formatted cleanly as "Makarios Avenue".
        
        3. PHONE NUMBER FORMATTING:
           - Standardize the phone number into a clean, valid format. Remove random hyphens that break the natural number layout (e.g., convert "966-543-21" into a clean 8-digit format like "96654321" or "+357 96 654321"). Ensure no spoken digits are lost.

        ### TARGET SCHEMA:
        {{
          "name": "string or 'Unknown'",
          "phone": "string or 'Unknown'",
          "address": "string or 'Unknown'",
          "summary": "1-sentence professional summary of the issue.",
          "priority": "Emergency" | "Standard"
        }}

        ### PHONE TRANSCRIPT:
        "{customer_transcript}"

        ### JSON OUTPUT:"""
    )

    # 2. Configure the IBM Granite Model via watsonx.ai
    granite_llm = WatsonxLLM(
        model_id="meta-llama/llama-3-3-70b-instruct",
        url="https://eu-de.ml.cloud.ibm.com",
        project_id=os.environ.get("WATSONX_PROJECT_ID"),
        params={
            "decoding_method": "greedy",
            "max_new_tokens": 300,
            "temperature": 0.0
        }
    )

    # 3. Use an Output Parser
    output_parser = JsonOutputParser()

    # 4. Construct the LCEL Chain
    dispatch_chain = prompt_template | granite_llm | output_parser

    print("Running transcript through IBM Granite...")
    structured_data = dispatch_chain.invoke({"customer_transcript": raw_transcript})
    
    return structured_data