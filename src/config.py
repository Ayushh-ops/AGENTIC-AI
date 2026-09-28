import os
from pathlib import Path
from dotenv import load_dotenv
from crewai import LLM

# Load .env from project root
ROOT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=ROOT_DIR / ".env")

def get_configured_llm(model_override: str = None, api_key_override: str = None) -> LLM:
    """
    Returns a configured CrewAI LLM instance based on available environment variables
    or optional overrides.
    """
    model_name = model_override or os.getenv("MODEL_NAME", "gemini/gemini-2.0-flash")

    # Determine provider & API key
    if "gemini" in model_name.lower():
        api_key = api_key_override or os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError(
                "GEMINI_API_KEY is not set. Please provide it in the .env file or UI settings."
            )
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    elif "groq" in model_name.lower():
        api_key = api_key_override or os.getenv("GROQ_API_KEY")
        if not api_key:
            raise ValueError(
                "GROQ_API_KEY is not set. Please provide it in the .env file or UI settings."
            )
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    elif "ollama" in model_name.lower():
        base_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        return LLM(model=model_name, base_url=base_url)

    else:
        # Default OpenAI or other LiteLLM compatible provider
        api_key = api_key_override or os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError(
                "OPENAI_API_KEY is not set. Please provide it in the .env file or UI settings."
            )
        return LLM(model=model_name, api_key=api_key, temperature=0.7)
