"""
LLM service module for interacting with the Groq API via direct HTTP.
"""

import contextvars
import re
import time
from typing import List, Optional
import httpx
from backend.app.core.config import settings

GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"

llm_call_counter: contextvars.ContextVar[Optional[list]] = contextvars.ContextVar(
    "llm_call_counter", default=None
)

# Statuses that trigger a key rotation before retry
_ROTATE_STATUSES = {429, 401, 403}


class LLMError(Exception):
    """Exception raised when an LLM operation fails or API key is missing."""
    pass


def _redact(key: str) -> str:
    """Return a safe placeholder — never include the real key in messages."""
    return "<redacted>"


def chat(
    system: str,
    user: str,
    temperature: float = 0.2,
    max_tokens: Optional[int] = None,
    api_keys: Optional[List[str]] = None,
) -> str:
    """
    Execute a chat completion request to Groq using httpx.

    Key rotation:
    - If *api_keys* is provided (non-empty), those keys are tried in order.
    - On HTTP 429, 401, or 403, the next key in the list is tried.
    - If all keys are exhausted, raises LLMError.
    - Falls back to settings.groq_api_key when api_keys is None or empty.

    Security: keys are never logged, never included in exception messages.

    Args:
        system: System prompt string providing persona/instructions.
        user: User prompt string with topic or content.
        temperature: Sampling temperature (default 0.2).
        max_tokens: Optional upper bound on generated tokens.
        api_keys: Optional per-request list of Groq API keys to rotate through.

    Returns:
        The text response content from the model.

    Raises:
        LLMError: If no API key is available or all keys fail.
    """
    counter = llm_call_counter.get()
    if counter is not None:
        counter.append(1)

    # Build ordered key list (request-scoped first, then .env fallback)
    keys_to_try: List[str] = []
    if api_keys:
        keys_to_try = list(api_keys)
    if not keys_to_try and settings.groq_api_key:
        keys_to_try = [settings.groq_api_key]

    if not keys_to_try:
        raise LLMError("No Groq API key configured. Add keys in Settings or in the backend .env.")

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

    max_retries_per_key = 2  # retries for network errors on same key
    last_error: Optional[Exception] = None

    for key_index, api_key in enumerate(keys_to_try):
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        for attempt in range(max_retries_per_key + 1):
            try:
                with httpx.Client(timeout=35.0) as client:
                    response = client.post(GROQ_API_URL, headers=headers, json=payload)

                    if response.status_code in _ROTATE_STATUSES:
                        # Rotate to the next key immediately
                        if response.status_code == 429 and attempt < max_retries_per_key and key_index == len(keys_to_try) - 1:
                            # Last key and still have retries: honour retry-after
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
                        # Break inner loop; try next key
                        last_error = LLMError(
                            f"Groq API returned status {response.status_code} (key rotated)."
                        )
                        break  # break the attempt loop → advance to next key

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
                if attempt < max_retries_per_key:
                    time.sleep(1.5)
                    continue
                last_error = LLMError("HTTP request to Groq failed after retries.")
                break
            except LLMError:
                raise
            except Exception as exc:
                raise LLMError(f"Unexpected error in LLM service.") from exc

    raise LLMError(
        "All Groq API keys failed. "
        + (str(last_error) if last_error else "Request failed after retries.")
    )
