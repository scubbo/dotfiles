---
name: granola
description: Read and search Granola meeting transcriptions, summaries, and notes from local storage
tags:
  - meetings
  - transcription
  - search
  - granola
---

---
name: granola
description: Use when you need to access meeting transcriptions, notes, or summaries from Granola app. Reads from local cache.
tags:
  - meetings
  - transcription
  - search
  - granola
---

# Granola Meeting Data Access

Read and search meeting data from the Granola app's local storage.

## Data Location

Granola stores data in `~/Library/Application Support/Granola/cache-v3.json`.

## Available Scripts

### list

List recent meetings with date, title, and attendee count.

```bash
skills_execute(skill_name="granola", script_name="list")
skills_execute(skill_name="granola", script_name="list", args=["--limit", "20"])
```

### list-for-day

List all meetings for a specific day. Defaults to today if no date provided.

```bash
skills_execute(skill_name="granola", script_name="list-for-day")
skills_execute(skill_name="granola", script_name="list-for-day", args=["2026-01-13"])
```

### search

Full-text search across transcripts, titles, and summaries.

```bash
skills_execute(skill_name="granola", script_name="search", args=["cache components"])
skills_execute(skill_name="granola", script_name="search", args=["OAuth", "--limit", "5"])
```

### read

Read a specific meeting's transcript and/or summary by ID.

```bash
skills_execute(skill_name="granola", script_name="read", args=["<meeting-id>"])
skills_execute(skill_name="granola", script_name="read", args=["<meeting-id>", "--transcript-only"])
skills_execute(skill_name="granola", script_name="read", args=["<meeting-id>", "--summary-only"])
```

### export

Export meeting data to markdown format.

```bash
skills_execute(skill_name="granola", script_name="export", args=["<meeting-id>"])
skills_execute(skill_name="granola", script_name="export", args=["<meeting-id>", "--output", "meeting.md"])
```

## Data Structure

Granola stores:
- **documents**: Meeting metadata (title, created_at, notes, calendar event)
- **transcripts**: Time-stamped speech segments with speaker source
- **documentPanels**: AI-generated summaries in ProseMirror format
- **meetingsMetadata**: Creator, attendees, conferencing details

## Privacy Note

Meeting transcripts contain sensitive content. All data stays local - no network calls.
