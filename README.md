# 🤖 AGENTIC-AI: Multi-Agent Research Assistant

Welcome to your **Agentic AI** project workspace! The entire development environment and tech stack have been fully installed and configured, giving you a clean slate to build your own custom Multi-Agent system from scratch.

---

## 🛠️ Pre-Installed Tech Stack in `.venv`

The virtual environment contains all the required libraries and tools:

| Component | Library / Package | Purpose |
|---|---|---|
| **Multi-Agent Framework** | `crewai`, `crewai-tools` | Build autonomous agents, assign tasks, manage crews & workflows |
| **Universal LLM Router** | `litellm` | Connect to Groq, Google Gemini, OpenAI, DeepSeek, Anthropic, Ollama |
| **Search & Web Retrieval** | `ddgs`, `wikipedia`, `requests`, `beautifulsoup4` | Live internet searching and document extraction |
| **Web Dashboard & UI** | `streamlit` | Build interactive web interfaces for your agents |
| **Configuration & Secrets** | `python-dotenv`, `pydantic` | Manage environment variables and structured outputs |

---

## 📁 Repository Structure

```
G:\multi_agent_research_assistant/
│
├── .venv/               # Virtual environment with all pre-installed libraries
├── .env.example         # Template for your API keys
├── .env                 # Local API keys (protected by .gitignore)
├── .gitignore           # Git ignore rules (prevents uploading .venv or secrets)
├── requirements.txt     # All project dependencies
└── README.md            # Project documentation
```

---

## 🚀 How to Start Developing

### 1. Activate the Virtual Environment
Open PowerShell inside this directory:
```powershell
.\.venv\Scripts\Activate.ps1
```

### 2. Configure Your API Keys
Open `.env` and add your preferred API keys:
```ini
GROQ_API_KEY=your_groq_key_here
GEMINI_API_KEY=your_gemini_key_here
OPENAI_API_KEY=your_openai_key_here
```

### 3. Create Your Agents and Start Building!
Create your Python files (e.g. `main.py` or your own structure) and begin developing your agents with CrewAI.
