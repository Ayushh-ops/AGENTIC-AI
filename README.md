# Multi-Agent Research Assistant

An autonomous, evidence-grounded research assistant that searches the live web, extracts and verifies factual claims, and synthesizes structured, cited Markdown research reports.

---

## 🛠️ Tech Stack Summary

* **Frontend Client**: **Flutter (Dart)** — Cross-platform client targeting Android, iOS, Desktop, and Web.
* **Backend API**: **FastAPI (Python 3.11+)** — High-concurrency async web server powered by Uvicorn.
* **Agent Orchestration**: **CrewAI** — Role-based autonomous workflow coordination (Researcher, Fact Checker, Synthesizer).
* **Live Web Research**: **Tavily Search & Tavily Extract** — Real-time search indexing and content extraction (Serper is not used).
* **LLM Inference Support**: Multi-provider support via **Google Gemini**, **Groq (Llama)**, and **OpenAI**.
* **Persistence Layer**: **SQLite** (local development) / **PostgreSQL** (production deployment).

---

## 📁 Repository Structure

```text
G:\multi_agent_research_assistant\
│
├── backend\                       # FastAPI backend service
│   ├── app\
│   │   ├── agents\                # CrewAI agent role definitions (Researcher, Verifier, Synthesizer)
│   │   ├── api\
│   │   │   └── routers\           # Modular API endpoints & route handlers
│   │   ├── core\                  # Security, utilities, and internal helpers
│   │   ├── db\                    # Database session management & engine
│   │   ├── models\                # Pydantic schemas and database models
│   │   ├── services\              # Business logic & background workers
│   │   ├── tasks\                 # CrewAI research task definitions
│   │   ├── tools\
│   │   │   ├── extract\           # Tavily web extraction tools
│   │   │   └── search\            # Tavily web search tools
│   │   ├── workflows\             # Crew orchestration pipelines
│   │   ├── config.py              # Type-safe environment settings
│   │   └── __init__.py
│   ├── tests\                     # Backend test suite (pytest)
│   │   ├── __init__.py
│   │   └── test_health.py         # Health check & config unit tests
│   ├── main.py                    # Canonical FastAPI app definition & /health endpoint
│   ├── requirements.txt           # Backend dependency manifest
│   └── __init__.py
│
├── frontend\                      # Cross-platform Flutter client
│   ├── lib\
│   │   ├── api\
│   │   │   ├── api_config.dart    # Dynamic host & base URL resolution
│   │   │   └── api_service.dart   # Asynchronous HTTP API client
│   │   ├── screens\
│   │   │   └── home_screen.dart   # Reactive connection validator screen
│   │   └── main.dart              # Flutter App entrypoint & Material 3 theme
│   ├── analysis_options.yaml      # Dart & Flutter linting rules
│   └── pubspec.yaml               # Flutter package manifest
│
├── .env.example                   # Master environment variables template
├── .env                           # Local environment secrets (Git-ignored)
├── .gitignore                     # Repository-wide ignore rules
├── helper.py                      # Root shared utilities (logging, environment diagnostics)
├── main.py                        # Root entrypoint to run the backend service
├── requirements.txt               # Master pinned Python dependencies
├── test.py                        # Root test runner invoking pytest
└── README.md                      # Project documentation
```

### Conceptual Architecture Mapping (College / Standard Pattern)
To align with standard industry and academic submission patterns, the modular package structure maps directly to generic design conventions:

| Generic Pattern | Project Path | Role in System |
|---|---|---|
| **API Entrypoint** | `backend/main.py` (exposed via root `main.py`) | FastAPI instantiation, CORS, and endpoint definitions |
| **Orchestrator** | `backend/app/workflows/` + `backend/app/agents/` | CrewAI agent loop, LLM dispatch, and task coordination |
| **Functions / Tools** | `backend/app/tools/` (`search/` & `extract/`) | Programmatic tools for Tavily search and content extraction |
| **Models / Schema** | `backend/app/models/` | Pydantic data schemas, request/response models, and entities |
| **Shared Helpers** | `helper.py` | Cross-cutting logging and environment verification utilities |
| **Test Suite** | `backend/tests/` (executed via root `test.py`) | Automated testing and verification suites |

---

## 🚀 Setup & Execution Guide

### 1. Environment Configuration
Create your local `.env` file from the root template:
```powershell
Copy-Item .env.example .env
```
Open `.env` and configure your API keys (Gemini, Groq, OpenAI, Tavily) as needed.

### 2. Python Environment & Dependencies
Activate the virtual environment and install dependencies:
```powershell
# From project root
.\.venv\Scripts\Activate.ps1

# Install dependencies using root requirements.txt
pip install -r requirements.txt
```

### 3. Run the Backend
Start the FastAPI backend service using the root entrypoint:
```powershell
python main.py
```
* Or directly via Uvicorn:
  ```powershell
  uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
  ```
* **Health Check**: `http://127.0.0.1:8000/health`
* **Swagger Documentation**: `http://127.0.0.1:8000/docs`

### 4. Run the Flutter Frontend
In a separate terminal, run the Flutter application:
```powershell
cd frontend
flutter pub get

# Android Emulator (automatically targets http://10.0.2.2:8000):
flutter run

# Physical Mobile Device (pass your computer's local Wi-Fi IP):
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000

# Web Browser / Desktop:
flutter run -d chrome
# or
flutter run -d windows
```

### 5. Run the Test Suite
Execute the automated test suite using the root test runner:
```powershell
python test.py
```
Or directly with pytest:
```powershell
pytest backend/tests -v
```
