"""Shared pytest-bdd fixtures and configuration for BDD tests."""

import os
import tempfile
from collections.abc import Generator
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Explicitly register step definition modules with pytest
pytest_plugins = [
    "step_defs.test_deployment_pipeline",
    "step_defs.test_local_development",
    "step_defs.test_framework_upgrade",
    "step_defs.test_framework_bootstrap",
]


@pytest.fixture
def temp_project_dir() -> Generator[Path, None, None]:
    """Create a temporary directory that mimics an Agile Flow project."""
    with tempfile.TemporaryDirectory() as temp_dir:
        project_path = Path(temp_dir)

        # Create basic project structure
        (project_path / ".git").mkdir()
        (project_path / "scripts").mkdir()
        (project_path / ".claude").mkdir()
        (project_path / "app").mkdir()
        (project_path / "tests").mkdir()
        (project_path / "features").mkdir()
        (project_path / "alembic").mkdir()
        (project_path / "alembic" / "versions").mkdir()

        # Create basic files
        (project_path / "pyproject.toml").write_text("""
[project]
name = "test-agile-flow"
version = "0.1.0"
requires-python = ">=3.12"

[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-bdd>=7.0"]
""")

        (project_path / "CLAUDE.md").write_text("# Test Project")

        (project_path / ".gembaflow-version").write_text("""
{
  "version": "1.0.0",
  "upstream": "vibeacademy/agile-flow-gcp",
  "syncDirectories": [
    "scripts/",
    ".github/workflows/",
    "docs/"
  ]
}
""")

        (project_path / "bootstrap.sh").write_text("""#!/bin/bash
echo "Agile Flow Bootstrap Wizard"
echo "Phase 0: Environment Setup"
echo "Phase 1: Product Definition"
echo "Phase 2: Technical Architecture"
echo "Phase 3: Agent Configuration"
echo "Phase 4: Project Board"
""")
        (project_path / "bootstrap.sh").chmod(0o755)

        (project_path / "scripts" / "setup-solo-mode.sh").write_text("""#!/bin/bash
echo "Configuring solo mode"
export AGILE_FLOW_SOLO_MODE=true
echo "solo mode is configured"
""")
        (project_path / "scripts" / "setup-solo-mode.sh").chmod(0o755)

        (project_path / "scripts" / "template-sync.sh").write_text("""#!/bin/bash
echo "Checking for updates..."
echo "No updates available"
""")
        (project_path / "scripts" / "template-sync.sh").chmod(0o755)

        (project_path / "scripts" / "hooks").mkdir()
        (project_path / "scripts" / "hooks" / "pre-push").write_text("""#!/bin/bash
# Pre-push hook
echo "Running pre-push checks..."
exit 0
""")
        (project_path / "scripts" / "hooks" / "pre-push").chmod(0o755)

        # Create app structure
        (project_path / "app" / "__init__.py").write_text("")
        (project_path / "app" / "main.py").write_text("""
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "Hello World"}
""")

        # Create Dockerfile
        (project_path / "Dockerfile").write_text("""
FROM python:3.12-slim
WORKDIR /app
COPY . /app
RUN pip install -e .
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
""")

        yield project_path


@pytest.fixture
def mock_subprocess():
    """Mock subprocess calls to avoid actual command execution."""
    with (
        patch("subprocess.run") as mock_run,
        patch("subprocess.check_output") as mock_check_output,
        patch("subprocess.Popen") as mock_popen,
    ):
        # Default successful responses
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        mock_check_output.return_value = b"mocked output"

        mock_process = MagicMock()
        mock_process.communicate.return_value = (b"stdout", b"stderr")
        mock_process.returncode = 0
        mock_popen.return_value = mock_process

        yield {"run": mock_run, "check_output": mock_check_output, "popen": mock_popen}


@pytest.fixture
def mock_git():
    """Mock git commands."""
    with patch("subprocess.run") as mock_run:

        def side_effect(cmd, *args, **kwargs):
            if isinstance(cmd, list) and cmd[0] == "git":
                if "status" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = "On branch main\nnothing to commit, working tree clean"
                    return result
                elif "remote" in cmd and "get-url" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = "https://github.com/user/repo.git"
                    return result
                elif "config" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = ""
                    return result

            # Default successful response
            result = MagicMock()
            result.returncode = 0
            result.stdout = ""
            return result

        mock_run.side_effect = side_effect
        yield mock_run


@pytest.fixture
def mock_gh_cli():
    """Mock GitHub CLI commands."""
    with patch("subprocess.run") as mock_run:

        def side_effect(cmd, *args, **kwargs):
            if isinstance(cmd, list) and cmd[0] == "gh":
                if "auth" in cmd and "token" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = "gho_test_token"
                    return result
                elif "api" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = '{"scopes": ["repo", "project", "workflow", "read:project"]}'
                    return result
                elif "repo" in cmd and "view" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = "Repository info"
                    return result

            # Default successful response
            result = MagicMock()
            result.returncode = 0
            result.stdout = ""
            return result

        mock_run.side_effect = side_effect
        yield mock_run


@pytest.fixture
def mock_gcloud():
    """Mock gcloud commands."""
    with patch("subprocess.run") as mock_run:

        def side_effect(cmd, *args, **kwargs):
            if isinstance(cmd, list) and cmd[0] == "gcloud":
                result = MagicMock()
                result.returncode = 0
                result.stdout = "Mocked gcloud output"
                return result

            # Default successful response
            result = MagicMock()
            result.returncode = 0
            result.stdout = ""
            return result

        mock_run.side_effect = side_effect
        yield mock_run


@pytest.fixture
def mock_docker():
    """Mock Docker commands."""
    with patch("subprocess.run") as mock_run:

        def side_effect(cmd, *args, **kwargs):
            if isinstance(cmd, list) and cmd[0] == "docker":
                if "build" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = "Successfully built image"
                    return result
                elif "push" in cmd:
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = "Image pushed successfully"
                    return result

            # Default successful response
            result = MagicMock()
            result.returncode = 0
            result.stdout = ""
            return result

        mock_run.side_effect = side_effect
        yield mock_run


@pytest.fixture
def mock_uvicorn():
    """Mock uvicorn server startup."""
    with patch("subprocess.Popen") as mock_popen:
        mock_process = MagicMock()
        mock_process.poll.return_value = None  # Still running
        mock_process.communicate.return_value = (
            b"INFO:     Uvicorn running on http://127.0.0.1:8080 (Press CTRL+C to quit)\n",
            b"",
        )
        mock_popen.return_value = mock_process
        yield mock_popen


@pytest.fixture(autouse=True)
def change_to_temp_dir(temp_project_dir):
    """Change working directory to temp project for all BDD tests."""
    original_cwd = os.getcwd()
    os.chdir(temp_project_dir)
    yield
    os.chdir(original_cwd)


# Store test context between steps
test_context = {}


@pytest.fixture
def context():
    """Shared test context for storing state between BDD steps."""
    global test_context
    test_context.clear()
    return test_context
