Feature: Framework Bootstrap
  As a developer
  I want to bootstrap my Agile Flow project
  So that I have a complete working environment

  Background:
    Given I have cloned the agile-flow-gcp repository
    And I am in the project root directory

  Scenario: Successful bootstrap with all required tools
    Given GitHub CLI is installed
    And Claude Code CLI is installed
    When I run the bootstrap script
    And I complete Phase 0 environment setup
    And I complete Phase 1 product definition
    And I complete Phase 2 technical architecture
    And I complete Phase 3 agent specialization
    And I complete Phase 4 workflow activation
    Then the bootstrap should complete successfully
    And I should see "Progress: [✓] Phase 0: Environment Setup"
    And I should see "Progress: [✓] Phase 1: Product Definition"
    And I should see "Progress: [✓] Phase 2: Technical Architecture"
    And I should see "Progress: [✓] Phase 3: Agent Specialization"
    And I should see "Progress: [✓] Phase 4: Workflow Activation"
    And the status file ".claude/.bootstrap-status" should exist
    And the status file should contain "phase4:complete"

  Scenario: Bootstrap fails when GitHub CLI is missing
    Given GitHub CLI is not installed
    When I run the bootstrap script
    Then the bootstrap should fail with error
    And I should see "gh CLI is not installed"
    And I should see installation instructions for GitHub CLI

  Scenario: Bootstrap fails when Claude Code CLI is missing
    Given GitHub CLI is installed
    And Claude Code CLI is not installed
    When I run the bootstrap script
    Then the bootstrap should fail with error
    And I should see "Claude Code CLI is not installed"
    And I should see installation instructions for Claude Code CLI

  Scenario: Resume bootstrap from previous phase
    Given I have partially completed bootstrap up to Phase 1
    When I run the bootstrap script again
    Then it should resume from Phase 2
    And Phase 0 and Phase 1 should show as complete
    And I should not need to re-enter Phase 0 and Phase 1 information

  Scenario: Shell profile configuration
    Given I have completed environment setup
    When the bootstrap configures environment variables
    Then AGILE_FLOW_WORKER_ACCOUNT should be added to my shell profile
    And AGILE_FLOW_REVIEWER_ACCOUNT should be added to my shell profile
    And the environment variables should be exported in current session
    And subsequent terminal sessions should have these variables available