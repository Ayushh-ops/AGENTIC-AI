"""
LLM service module for interacting with the Groq API via direct HTTP.
"""

import contextvars
import re
import time
from typing import Optional
import httpx
from backend.app.core.config import settings

GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"

llm_call_counter: contextvars.ContextVar[Optional[list]] = contextvars.ContextVar(
    "llm_call_counter", default=None
)


class LLMError(Exception):
    """Exception raised when an LLM operation fails or API key is missing."""
    pass


def chat(
    system: str,
    user: str,
    temperature: float = 0.2,
    max_tokens: Optional[int] = None,
) -> str:
    """
    Execute a chat completion request to Groq using httpx with automatic retry on 429.

    Args:
        system: System prompt string providing persona/instructions.
        user: User prompt string with topic or content.
        temperature: Sampling temperature (default 0.2).
        max_tokens: Optional upper bound on generated tokens.

    Returns:
        The text response content from the model.

    Raises:
        LLMError: If GROQ_API_KEY is not configured or the request fails.
    """
    counter = llm_call_counter.get()
    if counter is not None:
        counter.append(1)

    api_key = settings.groq_api_key
    if not api_key:
        raise LLMError("Groq API key is not configured.")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": settings.groq_model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": temperature,
    }
    if max_tokens is not None:
        payload["max_tokens"] = max_tokens

    max_retries = 3
    for attempt in range(max_retries + 1):
        try:
            with httpx.Client(timeout=35.0) as client:
                response = client.post(GROQ_API_URL, headers=headers, json=payload)
                if response.status_code == 429 and attempt < max_retries:
                    retry_after_str = response.headers.get("retry-after")
                    wait_time = None
                    if retry_after_str:
                        try:
                            wait_time = float(retry_after_str)
                        except ValueError:
                            pass
                    if wait_time is None:
                        m = re.search(r"try again in (\d+\.?\d*)s", response.text, re.IGNORECASE)
                        if m:
                            try:
                                wait_time = float(m.group(1)) + 0.5
                            except ValueError:
                                pass
                    if wait_time is None:
                        wait_time = 3.0 * (attempt + 1)
                    time.sleep(min(max(wait_time, 1.0), 10.0))
                    continue
                if response.status_code != 200:
                    raise LLMError(
                        f"Groq API error (status {response.status_code}): {response.text}"
                    )
                data = response.json()
                choices = data.get("choices", [])
                if not choices:
                    raise LLMError("Groq API returned an empty choices list.")
                content = choices[0].get("message", {}).get("content", "")
                return content.strip()
        except httpx.RequestError as exc:
            if attempt < max_retries:
                time.sleep(1.5)
                continue
            raise LLMError(f"HTTP request to Groq failed: {exc}") from exc
        except Exception as exc:
            if isinstance(exc, LLMError):
                raise
            raise LLMError(f"Unexpected error in LLM service: {exc}") from exc

    raise LLMError("Groq request failed after retries.")
