Feature: Deployment Pipeline
  As a developer with an Agile Flow project
  I want automated deployment to Cloud Run when I push to main
  So that my application is automatically deployed to production with proper CI/CD

  Background:
    Given I have an Agile Flow project configured for Google Cloud Platform
    And I have the required GitHub secrets configured
    And I am pushing changes to the main branch
    And the repository is not the upstream template (vibeacademy/gembaflow-gcp)

  Scenario: Deploy with Workload Identity Federation
    Given GCP_PROJECT_ID secret is configured
    And GCP_WORKLOAD_IDENTITY_PROVIDER secret is configured  
    And GCP_SERVICE_ACCOUNT secret is configured
    When I push changes to the main branch
    Then the deploy workflow should trigger
    And it should authenticate to Google Cloud using Workload Identity Federation
    And it should set up gcloud CLI
    And it should configure Docker for Artifact Registry
    And it should install uv and sync dependencies
    And it should run Alembic migrations if PRODUCTION_DATABASE_URL is set
    And it should build the container image with the git SHA tag
    And it should push the image to Artifact Registry
    And it should deploy to Cloud Run with the specified configuration
    And it should route 100% of traffic to the latest revision
    And it should display the deployed service URL
    And the workflow should complete successfully

  Scenario: Deploy with Service Account Key fallback
    Given GCP_PROJECT_ID secret is configured
    And GCP_SA_KEY secret is configured (instead of Workload Identity)
    When I push changes to the main branch  
    Then the deploy workflow should trigger
    And it should authenticate to Google Cloud using the service account key
    And it should proceed with the same deployment steps as Workload Identity
    And the deployment should complete successfully

  Scenario: Skip deployment when secrets are missing
    Given GCP_PROJECT_ID secret is not configured
    When I push changes to the main branch
    Then the deploy workflow should trigger
    And it should check for required secrets
    And it should output "GCP_PROJECT_ID not configured — skipping deployment"
    And it should skip all deployment steps
    And the workflow should complete with success status

  Scenario: Skip deployment on upstream template repository
    Given I am pushing to the vibeacademy/gembaflow-gcp repository
    When I push changes to the main branch
    Then the deploy workflow should not run
    And no deployment steps should execute
    And this prevents accidental deployment of the template itself

  Scenario: Database migration runs before deployment
    Given all deployment secrets are configured
    And PRODUCTION_DATABASE_URL secret is configured
    When I push changes to the main branch
    Then the workflow should run database migrations first
    And "uv run alembic upgrade head" should execute successfully
    And only then should the container build and deployment proceed
    And this ensures the database schema is updated before new code runs

  Scenario: Skip migrations when database URL not configured
    Given all deployment secrets are configured
    But PRODUCTION_DATABASE_URL secret is not set
    When I push changes to the main branch
    Then the workflow should skip the migration step
    And it should output "skipping migrations"
    And it should proceed directly to container build and deployment

  Scenario: Cloud Run service configuration is applied correctly
    Given the deployment workflow runs successfully
    When the service is deployed to Cloud Run
    Then it should use the specified service account for runtime
    And it should listen on port 8080
    And it should have 512Mi memory and 1 CPU allocated
    And it should allow 0 to 10 instances scaling
    And it should allow unauthenticated access
    And it should have ENVIRONMENT=production env var set
    And it should have DATABASE_URL env var set from secrets

  Scenario: Traffic routing updates after deployment
    Given the Cloud Run service already exists with previous revisions
    When a new deployment completes successfully
    Then the workflow should route 100% traffic to the latest revision
    And it should migrate traffic away from any previous revision pins
    And the service URL should serve the new revision immediately

  Scenario: CI checks run before deployment (via workflow_call)
    Given I push changes that trigger the deployment workflow
    When the deploy workflow calls the CI workflow
    Then all CI jobs should run (lint, typecheck, build, test, actionlint, python)
    And lint should check Markdown files with markdownlint
    And typecheck should validate JSON and version parity
    And build should run shellcheck on all shell scripts
    And test should validate command and agent files
    And actionlint should validate GitHub Actions workflows
    And python jobs should run ruff, mypy, pytest if pyproject.toml exists
    And all CI checks must pass before deployment proceeds