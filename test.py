"""
Multi-Agent Research Assistant - Root Test Runner

Convenience test runner to execute the backend test suite located in `backend/tests`.
Can be executed directly via `python test.py` or via pytest.
"""

import sys
import subprocess
from pathlib import Path


def run_tests() -> int:
    """Run backend test suite using pytest."""
    project_root = Path(__file__).resolve().parent
    tests_path = project_root / "backend" / "tests"

    print("=" * 60)
    print("Running Multi-Agent Research Assistant Backend Test Suite")
    print(f"Target: {tests_path}")
    print("=" * 60)

    try:
        import pytest

        # Ensure project root is on sys.path
        if str(project_root) not in sys.path:
            sys.path.insert(0, str(project_root))
        exit_code = pytest.main([str(tests_path), "-v"])
        return int(exit_code)
    except ImportError:
        # Fallback to subprocess if pytest is in virtual environment
        cmd = [sys.executable, "-m", "pytest", str(tests_path), "-v"]
        result = subprocess.run(cmd, cwd=str(project_root))
        return result.returncode


if __name__ == "__main__":
    sys.exit(run_tests())
