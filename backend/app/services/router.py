"""
Message Router Service: Classifies incoming user messages into 'chat' or 'research'
using fast rule-based matching with fallback to a minimal LLM classifier call.
Provides cost-saving canned responses for pure small talk without invoking LLM or Search APIs.
"""

import re
from typing import Optional, Tuple
from backend.app.services.llm_service import chat, LLMError

# Pure small-talk phrases (normalized: lowercase, punctuation removed, single spaces)
SMALL_TALK_PHRASES = {
    # Greetings
    "hi", "hello", "hey", "heyy", "heyyy", "hii", "hiii", "namaste", "namaskar",
    "pranam", "hola", "sup", "yo", "good morning", "good afternoon", "good evening",
    "good night", "good day",
    # Hinglish greetings & small talk
    "ram ram", "radhe radhe", "salaam", "salam", "kya haal hai", "kya haal",
    "kya hal hai", "kya chal raha hai", "aur batao", "kaise ho", "kaisa hai",
    "kaise hain", "kese ho", "kaise ho bhai", "kaisa hai bhai", "kese ho bhai",
    "kya haal h", "sab badhiya", "kya haal chaal", "kaise ho yaar",
    # Thanks
    "thanks", "thank you", "thank u", "thx", "ty", "many thanks", "shukriya",
    "dhanyavaad", "dhanyawad", "bahut dhanyavaad", "bahut shukriya", "thanks a lot",
    # Bye
    "bye", "goodbye", "bye bye", "tata", "see you", "cya", "alvida",
    # Acknowledgment / cool
    "ok", "okay", "cool", "sure", "got it", "alright", "fine", "k", "kk",
    "theek hai", "thik hai", "accha", "achha", "sahi hai",
    # Questions / identity / capability / help
    "how are you", "how are u", "how r u", "hows it going", "how is it going",
    "who are you", "who r u", "what are you", "tum kaun ho", "aap kaun ho", "kon ho tum",
    "what can you do", "what do you do", "tum kya kar sakte ho", "aap kya kar sakte ho",
    "kya kar sakte ho", "help", "madad", "help me",
}

# Honorifics / filler tokens that may be attached to small talk
FILLER_TOKENS_REGEX = re.compile(r"\b(bhai|bro|yaar|ji|there|friend|dude|sir|madam|bot|assistant)\b")

# Research intent triggers
RESEARCH_KEYWORDS = [
    "research", "latest", "news", "compare", "comparison", "explain",
    "what is", "what are", "tell me about", "report", "overview", "analysis",
]
YEAR_20XX_REGEX = re.compile(r"\b20\d{2}\b")

# Canned replies for pure small talk (zero LLM calls)
CANNED_REPLIES = {
    "default": (
        "Hello! I am a multi-agent research assistant. I can research any topic using live web search, "
        "cross-check and verify claims across independent sources, and compile a structured, cited report. "
        "What topic would you like me to research?"
    ),
    "thanks": (
        "You're welcome! I research topics using live web search, verify factual claims across independent "
        "sources, and synthesize cited research reports. What topic would you like to investigate next?"
    ),
    "bye": (
        "Goodbye! Whenever you need an in-depth research report with verified sources and claims, feel free to ask. "
        "Have a great day!"
    ),
}


def normalize_text(text: str) -> str:
    """Lowercase, strip non-alphanumeric characters (except whitespace), and collapse spaces."""
    cleaned = re.sub(r"[^\w\s]", " ", text.lower())
    return " ".join(cleaned.split())


def _is_small_talk(text_norm: str) -> bool:
    """Check if normalized text matches rule-based small talk."""
    if not text_norm:
        return False
    if text_norm in SMALL_TALK_PHRASES:
        return True

    # Strip conversational fillers (e.g., 'hello there' -> 'hello', 'kaise ho bhai' -> 'kaise ho')
    stripped = " ".join(FILLER_TOKENS_REGEX.sub(" ", text_norm).split())
    if stripped and stripped in SMALL_TALK_PHRASES:
        return True

    return False


CANNED_GREETING_PHRASES = {
    "hi", "hello", "hey", "heyy", "heyyy", "hii", "hiii", "namaste", "namaskar",
    "pranam", "hola", "sup", "yo", "good morning", "good afternoon", "good evening",
    "good night", "good day", "ram ram", "radhe radhe", "salaam", "salam",
    "kya haal hai", "kya haal", "kya hal hai", "kya chal raha hai", "aur batao",
    "kaise ho", "kaisa hai", "kaise hain", "kese ho", "kaise ho bhai", "kaisa hai bhai",
    "kese ho bhai", "kya haal h", "sab badhiya", "kya haal chaal", "kaise ho yaar",
    "how are you", "how are u", "how r u", "hows it going", "how is it going",
    "who are you", "who r u", "what are you", "tum kaun ho", "aap kaun ho", "kon ho tum",
    "what can you do", "what do you do", "tum kya kar sakte ho", "aap kya kar sakte ho",
    "kya kar sakte ho", "help", "madad", "help me",
}

CANNED_THANKS_PHRASES = {
    "thanks", "thank you", "thank u", "thx", "ty", "many thanks", "shukriya",
    "dhanyavaad", "dhanyawad", "bahut dhanyavaad", "bahut shukriya", "thanks a lot",
}

CANNED_BYE_PHRASES = {
    "bye", "goodbye", "bye bye", "tata", "see you", "cya", "alvida",
}


def check_canned(message: str) -> Tuple[bool, Optional[str]]:
    """
    Check if a message qualifies for a zero-cost canned reply
    (pure greetings, thanks, bye, 'who are you', 'what can you do').

    Returns:
        (True, canned_text) if matching, else (False, None).
    """
    text_norm = normalize_text(message)
    stripped = " ".join(FILLER_TOKENS_REGEX.sub(" ", text_norm).split())

    if text_norm in CANNED_THANKS_PHRASES or (stripped and stripped in CANNED_THANKS_PHRASES):
        return True, CANNED_REPLIES["thanks"]
    if text_norm in CANNED_BYE_PHRASES or (stripped and stripped in CANNED_BYE_PHRASES):
        return True, CANNED_REPLIES["bye"]
    if text_norm in CANNED_GREETING_PHRASES or (stripped and stripped in CANNED_GREETING_PHRASES):
        return True, CANNED_REPLIES["default"]

    return False, None


def classify(message: str) -> Tuple[str, str]:
    """
    Classify a message as 'chat' or 'research' with a descriptive reason.

    Order of evaluation:
    1. Rule-based small talk (0 LLM calls) -> 'chat'
    2. Clear research signals (0 LLM calls) -> 'research'
    3. Unclear / ambiguous fallback (1 tiny LLM call, max_tokens=5) -> 'chat' | 'research' (default 'research')

    Returns:
        (mode, reason) where mode is 'chat' or 'research'.
    """
    text_norm = normalize_text(message)
    words = text_norm.split()

    # Step 1a: Rule-based small talk
    if _is_small_talk(text_norm):
        return "chat", "rule_small_talk"

    # Step 1b: Clear research signals
    has_research_keyword = any(kw in text_norm for kw in RESEARCH_KEYWORDS)
    has_year = bool(YEAR_20XX_REGEX.search(text_norm))

    if has_research_keyword or has_year:
        return "research", "research_signal"

    # 3 or more words with no small-talk pattern
    if len(words) >= 3 and not _is_small_talk(text_norm):
        return "research", "clear_research_signal"

    # Step 1c: Unclear (e.g. 1-2 words that are not small talk, or ambiguous phrases)
    try:
        classifier_system = (
            "You are a message classifier. Reply with exactly one word: CHAT or RESEARCH."
        )
        classifier_user = f"Message: {message}\nClassification:"
        answer = chat(
            system=classifier_system,
            user=classifier_user,
            temperature=0.0,
            max_tokens=5,
        ).strip().upper()

        if "CHAT" in answer and "RESEARCH" not in answer:
            return "chat", "llm_classifier"
        elif "RESEARCH" in answer:
            return "research", "llm_classifier"
        else:
            return "research", "llm_default"
    except (LLMError, Exception):
        return "research", "llm_fallback"
