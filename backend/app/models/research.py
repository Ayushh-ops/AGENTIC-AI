"""
Pydantic models for research requests, responses, sources, and claims.
"""

from typing import List, Optional
from pydantic import BaseModel, Field, field_validator


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
