Feature: Local Development Environment
  As a developer working on an Agile Flow project
  I want to run my application locally with proper tooling
  So that I can develop and test features efficiently before deploying

  Background:
    Given I am in an Agile Flow project directory
    And I have Python 3.12+ and uv package manager installed
    And I have completed the framework bootstrap setup
    And I have a valid pyproject.toml file

  Scenario: Install development dependencies
    Given I have not installed project dependencies
    When I run "uv sync --extra dev"
    Then all production dependencies should be installed
    And all development dependencies should be installed
    And the virtual environment should be created or updated
    And I should see "Resolved X packages" in the output
    And the command should exit with code 0

  Scenario: Start local development server
    Given dependencies are installed via uv sync
    When I run "uv run uvicorn app.main:app --reload --port 8080"
    Then the FastAPI application should start
    And the development server should listen on port 8080
    And it should enable auto-reload for code changes
    And I should see "Uvicorn running on http://127.0.0.1:8080" in the output
    And the application should respond to HTTP requests on localhost:8080

  Scenario: Run code quality checks
    Given dependencies are installed
    When I run the lint command "uv run ruff check ."
    Then it should check all Python files for style violations
    And it should exit with code 0 if no violations are found
    And it should report specific violations if any are found
    
    When I run the format command "uv run ruff format ."
    Then it should format Python files according to project style
    And it should report which files were reformatted
    
    When I run the type check command "uv run mypy app/"
    Then it should perform static type checking on the app directory
    And it should report any type errors found

  Scenario: Run test suite
    Given dependencies are installed
    When I run "uv run pytest"
    Then it should discover and run all test files
    And it should report test results and coverage
    And it should exit with code 0 if all tests pass
    And it should exit with non-zero code if any tests fail

  Scenario: Run test suite with coverage reporting
    Given dependencies are installed  
    When I run "uv run pytest --cov=app --cov-report=term-missing"
    Then it should run tests with coverage tracking
    And it should report coverage percentage for the app module
    And it should show which lines are missing coverage
    And it should exit with code 0 if tests pass and coverage meets threshold

  Scenario: Run database migrations
    Given dependencies are installed
    And I have a valid DATABASE_URL configured
    When I run "uv run alembic upgrade head"
    Then it should apply all pending database migrations
    And it should update the migration history table
    And it should report successful migration completion

  Scenario: Create new database migration
    Given dependencies are installed
    And I have made changes to SQLModel models
    When I run "uv run alembic revision --autogenerate -m 'Add new feature'"
    Then it should generate a new migration file
    And the migration should detect model changes automatically
    And the migration file should be created in alembic/versions/
    And it should contain upgrade and downgrade functions

  Scenario: Build container image locally
    Given I have Docker installed and running
    And I am in the project root directory
    When I run "docker build -t agile-flow-app ."
    Then it should build a container image using the Dockerfile
    And it should install dependencies in the container
    And it should set up the application for production
    And the build should complete successfully
    And I should have a tagged image "agile-flow-app" available locally