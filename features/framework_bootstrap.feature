Feature: Framework Bootstrap
  As a developer setting up a new Agile Flow project
  I want to bootstrap my development environment
  So that I can start working on my project with proper tooling and configuration

  Background:
    Given I am in a freshly cloned Agile Flow project directory
    And I have git, gh CLI, and required dependencies installed
    And I have a valid GitHub account with admin access to the repository

  Scenario: Solo mode setup completes successfully
    Given I have not run the bootstrap setup before
    When I run "bash scripts/setup-solo-mode.sh"
    Then the script should detect my shell profile
    And AGILE_FLOW_SOLO_MODE should be set to "true" in my shell profile
    And the script should audit GITHUB_PERSONAL_ACCESS_TOKEN env vars
    And my gh token should have required scopes (repo, project, workflow, read:project)
    And the pre-push hook should be activated with "scripts/hooks"
    And I should have admin access on the current fork
    And canonical GitHub labels should be set up (P0, P1, P2, P3, epic)
    And CLAUDE.md project config should be populated from git remote
    And the script should exit with code 0
    And I should see "solo mode is configured" in the output

  Scenario: Bootstrap wizard runs all phases
    Given solo mode setup has completed successfully
    When I run "bash bootstrap.sh"
    Then I should see the Agile Flow Bootstrap Wizard header
    And I should see progress showing Phase 0 through Phase 4
    And the script should guide me through environment setup
    And the script should prompt for product definition via Claude Code
    And the script should prompt for technical architecture via Claude Code
    And the script should prompt for agent configuration via Claude Code
    And the script should prompt for project board setup via Claude Code
    And each completed phase should be marked in ".claude/.bootstrap-status"

  Scenario: Pre-push hook prevents bad commits
    Given the bootstrap setup has completed
    And the pre-push hook is activated
    When I create a commit with failing lint or tests
    And I attempt to push the changes
    Then the pre-push hook should run lint and tests
    And the push should be rejected if tests fail
    And I should see the specific failing checks in the output
    And no changes should be pushed to the remote repository