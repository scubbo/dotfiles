#!/usr/bin/env python3
"""
Shared parser for Granola cache data.
Provides functions to load and extract meeting data from the local cache.
"""

import json
import os
from pathlib import Path
from datetime import datetime
from typing import Optional

GRANOLA_CACHE_PATH = Path.home() / "Library/Application Support/Granola/cache-v3.json"


def load_cache() -> dict:
    """Load and parse the Granola cache file."""
    if not GRANOLA_CACHE_PATH.exists():
        raise FileNotFoundError(f"Granola cache not found at {GRANOLA_CACHE_PATH}")

    with open(GRANOLA_CACHE_PATH, "r") as f:
        data = json.load(f)

    # The cache contains nested JSON
    inner = json.loads(data["cache"])
    return inner["state"]


def prosemirror_to_text(node: dict, depth: int = 0) -> str:
    """Convert ProseMirror JSON to plain text."""
    if not isinstance(node, dict):
        return ""

    result = []
    node_type = node.get("type", "")

    # Handle text nodes
    if node_type == "text":
        return node.get("text", "")

    # Handle structural nodes
    prefix = ""
    suffix = ""

    if node_type == "heading":
        level = node.get("attrs", {}).get("level", 1)
        prefix = "#" * level + " "
        suffix = "\n"
    elif node_type == "paragraph":
        suffix = "\n"
    elif node_type == "bulletList":
        pass  # Children handle bullets
    elif node_type == "listItem":
        prefix = "- "
    elif node_type == "orderedList":
        pass  # Children handle numbers

    # Process children
    content = node.get("content", [])
    child_texts = []
    for child in content:
        child_text = prosemirror_to_text(child, depth + 1)
        if child_text:
            child_texts.append(child_text)

    inner_text = "".join(child_texts)

    if prefix or suffix:
        return prefix + inner_text + suffix
    return inner_text


def get_documents(state: dict) -> list[dict]:
    """Get all documents sorted by creation date (newest first)."""
    documents = state.get("documents", {})
    doc_list = list(documents.values())

    # Sort by created_at descending
    doc_list.sort(key=lambda d: d.get("created_at", ""), reverse=True)
    return doc_list


def get_document_by_id(state: dict, doc_id: str) -> Optional[dict]:
    """Get a specific document by ID."""
    documents = state.get("documents", {})
    return documents.get(doc_id)


def get_transcript(state: dict, doc_id: str) -> list[dict]:
    """Get transcript segments for a document, sorted by timestamp."""
    transcripts = state.get("transcripts", {})
    segments = transcripts.get(doc_id, [])

    if isinstance(segments, list):
        segments.sort(key=lambda s: s.get("start_timestamp", ""))
        return segments
    return []


def get_summary(state: dict, doc_id: str) -> Optional[str]:
    """Get the AI-generated summary for a document as plain text."""
    panels = state.get("documentPanels", {})
    doc_panels = panels.get(doc_id, {})

    if not isinstance(doc_panels, dict):
        return None

    # Find the summary panel
    for panel_id, panel_data in doc_panels.items():
        if isinstance(panel_data, dict):
            title = panel_data.get("title", "").lower()
            if "summary" in title:
                content = panel_data.get("content", {})
                if isinstance(content, dict):
                    return prosemirror_to_text(content).strip()

    return None


def get_meeting_metadata(state: dict, doc_id: str) -> Optional[dict]:
    """Get meeting metadata (attendees, creator, etc.)."""
    metadata = state.get("meetingsMetadata", {})
    return metadata.get(doc_id)


def format_timestamp(iso_str: str) -> str:
    """Format an ISO timestamp to a readable string."""
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d %H:%M")
    except (ValueError, AttributeError):
        return iso_str


def format_date(iso_str: str) -> str:
    """Format an ISO timestamp to just the date."""
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d")
    except (ValueError, AttributeError):
        return iso_str


def parse_date(date_str: str) -> datetime:
    """Parse a date string (YYYY-MM-DD) to datetime."""
    return datetime.strptime(date_str, "%Y-%m-%d")


def transcript_to_text(segments: list[dict]) -> str:
    """Convert transcript segments to readable text."""
    lines = []
    for seg in segments:
        time = format_timestamp(seg.get("start_timestamp", ""))
        text = seg.get("text", "")
        source = seg.get("source", "unknown")
        lines.append(f"[{time}] ({source}) {text}")
    return "\n".join(lines)
