"""
Core configuration settings for the Multi-Agent Research Assistant backend.
Powered by pydantic-settings for robust environment variable management.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: str = "development"
    openai_api_key: str | None = None
    gemini_api_key: str | None = None
    groq_api_key: str | None = Field(default=None, alias="GROQ_API_KEY")
    groq_model: str = Field(default="llama-3.3-70b-versatile", alias="GROQ_MODEL")
    tavily_api_key: str | None = Field(default=None, alias="TAVILY_API_KEY")
    database_url: str = "sqlite:///./research_assistant.db"


settings = Settings()
