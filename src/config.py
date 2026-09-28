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
    or user-provided overrides.
    """
    model_name = model_override or os.getenv("MODEL_NAME", "gemini/gemini-2.0-flash")

    # Normalize model prefix
    lower_model = model_name.lower()

    if "gemini" in lower_model:
        api_key = api_key_override or os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY is not set. Please enter your Gemini API key.")
        os.environ["GEMINI_API_KEY"] = api_key
        # Ensure prefix format
        if not model_name.startswith("gemini/"):
            model_name = f"gemini/{model_name}"
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    elif "groq" in lower_model:
        api_key = api_key_override or os.getenv("GROQ_API_KEY")
        if not api_key:
            raise ValueError("GROQ_API_KEY is not set. Please enter your Groq API key.")
        os.environ["GROQ_API_KEY"] = api_key
        if not model_name.startswith("groq/"):
            model_name = f"groq/{model_name}"
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    elif "deepseek" in lower_model:
        api_key = api_key_override or os.getenv("DEEPSEEK_API_KEY")
        if not api_key:
            raise ValueError("DEEPSEEK_API_KEY is not set. Please enter your DeepSeek API key.")
        os.environ["DEEPSEEK_API_KEY"] = api_key
        if not model_name.startswith("deepseek/"):
            model_name = f"deepseek/{model_name}"
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    elif "ollama" in lower_model:
        base_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        return LLM(model=model_name, base_url=base_url)

    else:
        # Default OpenAI / LiteLLM provider
        api_key = api_key_override or os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY is not set. Please enter your OpenAI API key.")
        os.environ["OPENAI_API_KEY"] = api_key
        return LLM(model=model_name, api_key=api_key, temperature=0.7)
