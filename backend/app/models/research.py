"""
Pydantic models for research requests, responses, sources, and claims.
"""

from enum import Enum
from typing import Any, List, Optional
from pydantic import BaseModel, Field, field_validator


class ResearchType(str, Enum):
    general = "general"
    news = "news"
    academic = "academic"


class ResearchDepth(str, Enum):
    quick = "quick"
    standard = "standard"
    deep = "deep"


class ResearchRequest(BaseModel):
    """Payload for submitting a research query."""
    topic: str = Field(
        ...,
        min_length=1,
        max_length=200,
        description="The research topic to investigate.",
    )

    @field_validator("topic")
    @classmethod
    def validate_non_empty_topic(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Topic must not be empty or whitespace only.")
        return stripped


class SourceItem(BaseModel):
    """Metadata and content snippet for a consulted web source."""
    title: str = Field(default="", description="Webpage or document title.")
    url: str = Field(..., description="Canonical source URL.")
    content: str = Field(default="", description="Relevant extracted snippet or text.")


class ClaimItem(BaseModel):
    """A factual claim evaluated during research."""
    statement: str = Field(..., description="The factual assertion.")
    status: str = Field(
        ...,
        description="Verification status: 'supported' (>=2 domains), 'single_source' (1 domain), or 'unsupported'.",
    )
    evidence: str = Field(
        default="",
        description="Direct excerpt from source text substantiating the claim (max ~200 chars).",
    )
    source_urls: List[str] = Field(
        default_factory=list,
        description="List of supporting source URLs.",
    )
    source_url: Optional[str] = Field(
        default=None,
        description="Supporting source URL if verified (primary URL retained for backward compatibility).",
    )


class ResearchResponse(BaseModel):
    """Consolidated research report output."""
    topic: str
    report_markdown: str
    sources: List[SourceItem]
    claims: List[ClaimItem]


class AskRequest(BaseModel):
    """Payload for submitting a message or query to POST /ask."""
    message: str = Field(
        ...,
        min_length=1,
        max_length=200,
        description="User message or research topic (non-empty, max 200 characters).",
    )
    research_type: Optional[ResearchType] = Field(
        default=ResearchType.general,
        description="Optional research type: 'general' | 'news' | 'academic' (default 'general').",
    )
    depth: Optional[ResearchDepth] = Field(
        default=ResearchDepth.standard,
        description="Optional research depth: 'quick' | 'standard' | 'deep' (default 'standard').",
    )

    @field_validator("message")
    @classmethod
    def validate_non_empty_message(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Message must not be empty or whitespace only.")
        return stripped

    @field_validator("research_type", mode="before")
    @classmethod
    def default_research_type(cls, value: Any) -> Any:
        if value is None:
            return ResearchType.general
        return value

    @field_validator("depth", mode="before")
    @classmethod
    def default_depth(cls, value: Any) -> Any:
        if value is None:
            return ResearchDepth.standard
        return value


class AskResponse(BaseModel):
    """Consolidated response model for POST /ask."""
    mode: str = Field(..., description="'chat' or 'research'")
    reply: Optional[str] = Field(default=None, description="Chat reply text if mode is chat")
    research: Optional[ResearchResponse] = Field(default=None, description="Research results if mode is research")
    llm_calls: Optional[int] = Field(default=None, description="Number of LLM calls made")
    search_calls: Optional[int] = Field(default=None, description="Number of search calls made")
