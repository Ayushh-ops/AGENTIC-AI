import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Enforce UTF-8 encoding on Windows
os.environ["PYTHONIOENCODING"] = "utf-8"

# 1. Configure LiteLLM to drop unsupported provider parameters
try:
    import litellm
    litellm.drop_params = True
except Exception:
    pass

# 2. Patch CrewAI cache_breakpoint to avoid Groq schema validation rejection
try:
    import crewai.llms.cache
    crewai.llms.cache.mark_cache_breakpoint = lambda msg: msg
except Exception:
    pass

from crewai import LLM

# Load .env from project root
ROOT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=ROOT_DIR / ".env")

def get_configured_llm(model_override: str = None, api_key_override: str = None) -> LLM:
    """
    Returns a configured CrewAI LLM instance based on available environment variables
    or user-provided overrides.
    """
    model_name = model_override or os.getenv("MODEL_NAME", "groq/llama-3.3-70b-versatile")
    lower_model = model_name.lower().strip()

    # 1. Groq Models
    if "groq" in lower_model:
        api_key = api_key_override or os.getenv("GROQ_API_KEY")
        if not api_key:
            raise ValueError("GROQ_API_KEY is not set. Please enter your Groq API key.")
        os.environ["GROQ_API_KEY"] = api_key
        if not model_name.startswith("groq/"):
            model_name = f"groq/{model_name}"
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    # 2. Google Gemini Models
    elif "gemini" in lower_model:
        api_key = api_key_override or os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY is not set. Please enter your Gemini API key.")
        os.environ["GEMINI_API_KEY"] = api_key
        if not model_name.startswith("gemini/"):
            model_name = f"gemini/{model_name}"
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    # 3. DeepSeek Models
    elif "deepseek" in lower_model:
        api_key = api_key_override or os.getenv("DEEPSEEK_API_KEY")
        if not api_key:
            raise ValueError("DEEPSEEK_API_KEY is not set. Please enter your DeepSeek API key.")
        os.environ["DEEPSEEK_API_KEY"] = api_key
        if not model_name.startswith("deepseek/"):
            model_name = f"deepseek/{model_name}"
        return LLM(model=model_name, api_key=api_key, temperature=0.7)

    # 4. Ollama Local Models
    elif "ollama" in lower_model:
        base_url = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
        return LLM(model=model_name, base_url=base_url)

    # 5. OpenAI & Default Providers
    else:
        api_key = api_key_override or os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY is not set. Please enter your OpenAI API key.")
        os.environ["OPENAI_API_KEY"] = api_key
        return LLM(model=model_name, api_key=api_key, temperature=0.7)
