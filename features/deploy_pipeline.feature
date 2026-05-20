Feature: Deploy Pipeline
  As a developer
  I want automated deployment to Google Cloud Run
  So that my application is available in production

  Background:
    Given I have an Agile Flow GCP project
    And the repository is configured with required secrets
    And I am not working on the upstream template repository

  Scenario: Successful CI pipeline
    Given I have created a pull request
    When the CI workflow runs
    Then it should lint markdown files
    And it should validate JSON files  
    And it should validate version parity
    And it should validate shell scripts with shellcheck
    And it should validate command files
    And it should validate agent files
    And it should run actionlint on workflow files
    And it should run Python linting with ruff
    And it should run Python type checking with mypy
    And it should run Python tests with pytest
    And it should run BDD tests if feature files exist
    And all CI checks should pass

  Scenario: Production deployment with Workload Identity Federation
    Given I push to the main branch
    And GCP_PROJECT_ID secret is configured
    And GCP_WORKLOAD_IDENTITY_PROVIDER secret is configured
    And GCP_SERVICE_ACCOUNT secret is configured
    When the deploy workflow runs
    Then it should authenticate to GCP using Workload Identity Federation
    And it should set up gcloud
    And it should configure Docker for Artifact Registry
    And it should install uv
    And it should run Alembic migrations against production database
    And it should build the Docker container
    And it should push the container to Artifact Registry
    And it should deploy to Cloud Run with correct configuration
    And it should route 100% traffic to the latest revision
    And it should display the deployed URL

  Scenario: Production deployment with Service Account Key fallback
    Given I push to the main branch
    And GCP_PROJECT_ID secret is configured
    And GCP_SA_KEY secret is configured (not WIF)
    When the deploy workflow runs
    Then it should authenticate to GCP using service account key
    And the deployment should proceed normally
    And the application should be deployed successfully

  Scenario: Skip deployment when secrets not configured
    Given I push to the main branch
    And GCP_PROJECT_ID secret is not configured
    When the deploy workflow runs
    Then it should skip deployment
    And I should see "GCP_PROJECT_ID not configured — skipping deployment"
    And I should see setup instructions reference

  Scenario: Skip deployment on upstream repository
    Given I am working on "vibeacademy/agile-flow-gcp" repository
    When I push to the main branch
    Then the deploy workflow should not run
    And no deployment attempt should be made

  Scenario: Database migration handling
    Given I push to the main branch with schema changes
    And PRODUCTION_DATABASE_URL secret is configured
    When the deploy workflow runs
    Then it should run "uv run alembic upgrade head" 
    And migrations should be applied before container deployment
    And the new container should work with the updated schema

  Scenario: Container build and registry push
    Given the deploy workflow is running
    When it reaches the container build step
    Then it should build with the current commit SHA as tag
    And the image should be tagged as "$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/$ARTIFACT_REPO/$SERVICE_NAME:$GITHUB_SHA"
    And it should push to Google Artifact Registry
    And the image should be available for deployment

  Scenario: Cloud Run service configuration
    Given the container is built and pushed
    When the deployment step runs
    Then it should deploy to Cloud Run with:
      | setting | value |
      | port | 8080 |
      | memory | 512Mi |  
      | cpu | 1 |
      | min-instances | 0 |
      | max-instances | 10 |
      | allow-unauthenticated | true |
    And it should use the configured service account
    And it should set environment variables for production

  Scenario: Traffic routing to latest revision
    Given a new revision is deployed successfully
    When the traffic routing step runs
    Then it should run "gcloud run services update-traffic"
    And it should route 100% traffic to the latest revision
    And the routing should be idempotent