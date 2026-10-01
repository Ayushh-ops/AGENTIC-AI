"""
Application configuration re-export for backwards compatibility.
Canonical settings are defined in backend.app.core.config.
"""

from backend.app.core.config import Settings, settings

__all__ = ["Settings", "settings"]
