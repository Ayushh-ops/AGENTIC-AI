# Multi Agent Research Assistant

> Research that shows its work: live web search, cross-checked claims, cited reports.

---

## How It Works

The assistant coordinates three specialized agents in an automated research and verification pipeline:

- **Researcher**: Deconstructs the research topic into focused, concise search queries (or uses the raw topic in Quick mode), queries the live web via the Tavily Search API filtered by the selected research type, skips low-quality or social domains, extracts text excerpts, and returns deduplicated web sources.
- **Fact-Checker**: Extracts key factual statements up to the depth-configured limit, validates that every claim quote appears verbatim in the source excerpts (with punctuation-normalized and fuzzy matching fallback), groups sources by independent registrable domains, runs targeted fallback searches for uncorroborated claims, and assigns verification statuses.
- **Synthesizer**: Synthesizes verified claims and cited sources into an auditable Markdown report containing an Executive Summary, Key Findings, an Evaluated Claims & Verification Audit table, and References. Unsupported claims are strictly excluded from findings and summaries.

---

## Claim Labels & Verification

Every evaluated claim is assigned an explicit verification status:

- **Corroborated**: 2 or more independent registrable domains (e.g. distinct root domains, ignoring subdomains) substantiate the claim with validated quotes.
- **Single source**: Exactly 1 verified source substantiates the claim. Treated as an unconfirmed lead rather than an established fact.
- **Unsupported**: No verified source backed up the claim, or the extracted quote failed text validation against the retrieved source content.

*All claim quotes are strictly validated against retrieved source text before acceptance.*

---

## Research Types & Depth Settings

### Types
- **General**: Comprehensive multi-domain search across authoritative public web sources.
- **News**: Prioritizes timely reporting, current events, and journalistic news publishers.
- **Academic**: Filters for scholarly publications, research papers, and educational repositories.

### Depth Matrix (from `DEPTH_SETTINGS`)

| Depth | Max Claims | Key Findings | Summary Length | Max Queries | Source Cap | Fallback Searches | Excerpt Length |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Quick** | 3 | 3 | 2–3 sentences (~70 words) | 1 (topic itself) | 8 | 0 | 800 chars |
| **Standard** | 5 | 5 | ~130 words | Up to 3 | 12 | Up to 3 | 800 chars |
| **Deep** | 8 | 7 | ~220 words | Up to 4 | 20 | Up to 6 | 600 chars |

---

## Features

- **Landing & Explanations**: Clean hero presentation, interactive topic composer, live pipeline walk-through, and verification criteria guide.
- **Unified Workspace**: Fixed-height top bar (64px) with persistent navigation, secondary search controls during active runs, and expandable sidebar.
- **Composer & Filters**: Multi-line topic composer with live character indicator, fast type selector pills, and depth configuration popover.
- **Search History**: Client-side research history grouped by timestamp (Today, Yesterday, Earlier) with quick reload and deletion.
- **Export & Import**: Download reports directly in the browser as Markdown (`.md`) or structured JSON (`.json`); import valid JSON reports back into your history.
- **Theming & Motion**: Dark and light modes with custom accent tokens, cursor-following grid spotlight, and smooth animated transitions.

---

## System Limits & Disclaimers

- **Topic Length**: Maximum of 200 characters per topic.
- **No Caching**: Every run performs live web searches and fresh LLM evaluations.
- **AI-Generated**: Reports are AI-generated and unverified by humans; always inspect the cited evidence and quotes under each claim.
- **Rate Limits**: Subject to external provider quotas (Tavily search requests and Groq LLM inference limits).

---

## Tech Stack

- **Frontend**: Flutter Web (Dart)
- **Backend API**: FastAPI (Python 3.11+) & Uvicorn
- **Live Search**: Tavily Search API
- **LLM Inference**: Groq API via direct REST service (`llama-3.3-70b-versatile` by default)

---

## Setup & Installation

### Prerequisites
- Python 3.11+
- Flutter SDK 3.x
- Active API keys for **Groq** and **Tavily**

### 1. Backend Setup

```bash
# Create and activate virtual environment
python -m venv .venv
# On Windows:
.\.venv\Scripts\Activate.ps1
# On macOS/Linux:
# source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
cp .env.example .env
# Edit .env and enter your GROQ_API_KEY and TAVILY_API_KEY

# Start backend server
uvicorn backend.main:app --reload --port 8000
```

The API will be available at `http://127.0.0.1:8000` (docs at `http://127.0.0.1:8000/docs`).

### 2. Frontend Setup

```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Run in Chrome
flutter run -d chrome
```

---

## Running Tests

### Backend Tests (pytest)
```bash
pytest backend/tests
```

### Frontend Tests (flutter test)
```bash
cd frontend
flutter test
```

---

## Project Structure

```text
multi_agent_research_assistant/
├── backend/
│   ├── app/
│   │   ├── agents/          # Researcher, Fact-Checker, and Synthesizer agents
│   │   ├── api/             # FastAPI routers and endpoints
│   │   ├── core/            # Configuration and application settings
│   │   ├── models/          # Pydantic schemas (claims, sources, reports)
│   │   ├── services/        # Groq LLM service & Tavily search service
│   │   └── workflows/       # Orchestration workflow & DEPTH_SETTINGS
│   ├── tests/               # Backend pytest test suite
│   ├── main.py              # FastAPI application entrypoint
│   └── requirements.txt     # Python dependencies
├── frontend/
│   ├── lib/
│   │   ├── api/             # API client and service bindings
│   │   ├── screens/         # HomeScreen (landing and workspace UI)
│   │   ├── theme/           # AppTheme color palettes and typography
│   │   └── main.dart        # Flutter entrypoint
│   ├── test/                # Flutter widget and unit tests
│   └── pubspec.yaml         # Flutter package dependencies
├── .env.example             # Environment template (no secrets)
├── .gitignore               # Ignored files (.env, build/, .dart_tool/, etc.)
└── README.md                # Project documentation
```
