"""
Multi-Agent Research Assistant - Shared Helper Module

Provides cross-cutting utilities and project-level helpers shared across
scripts, runners, and diagnostic tools (independent of specific backend or frontend code).
"""

import os
import logging
from pathlib import Path
from typing import Dict, Any
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent


def get_project_root() -> Path:
    """Return the absolute Path to the repository root directory."""
    return PROJECT_ROOT


def get_logger(name: str = "assistant") -> logging.Logger:
    """
    Return a pre-configured logger with standardized formatting across the application.
    """
    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        formatter = logging.Formatter(
            fmt="%(asctime)s | %(levelname)-7s | %(name)s | %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
        handler = logging.StreamHandler()
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    return logger


def load_env() -> bool:
    """Safely load .env file from the project root if it exists."""
    env_path = PROJECT_ROOT / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path)
        return True
    return False


def check_env_status() -> Dict[str, Any]:
    """
    Diagnostic helper to verify configured environment variables without exposing secret values.
    """
    load_env()
    tracked_keys = [
        "ENVIRONMENT",
        "OPENAI_API_KEY",
        "GEMINI_API_KEY",
        "GROQ_API_KEY",
        "TAVILY_API_KEY",
        "DATABASE_URL",
    ]
    return {
        key: ("Configured" if bool(os.getenv(key)) else "Missing/Unset")
        for key in tracked_keys
    }


if __name__ == "__main__":
    logger = get_logger("diagnostic")
    logger.info("Project Root: %s", get_project_root())
    status = check_env_status()
    for k, v in status.items():
        logger.info("Environment variable %s: %s", k, v)
