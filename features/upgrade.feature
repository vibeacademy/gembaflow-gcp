Feature: Framework Upgrade
  As a developer
  I want to upgrade my Agile Flow framework files
  So that I can get the latest features and bug fixes

  Background:
    Given I have an Agile Flow project
    And I am in the project root directory
    And the ".gembaflow-version" file exists

  Scenario: Successful upgrade to newer version
    Given my local version is "0.9.0"
    And the latest upstream version is "1.0.0"  
    And my working tree is clean
    And GitHub CLI is authenticated
    When I run the upgrade command
    Then it should download the latest release tarball
    And it should sync files from syncDirectories
    And it should create a new branch "agile-flow-sync/v1.0.0"
    And it should update ".gembaflow-version" to "1.0.0"
    And it should commit the changes with message "chore(sync): update Agile Flow framework to v1.0.0"
    And it should push the branch to origin
    And it should create a pull request
    And I should see "PR created successfully for v1.0.0"

  Scenario: Already up to date
    Given my local version is "1.0.0"
    And the latest upstream version is "1.0.0"
    When I run the upgrade command  
    Then I should see "No updates available. Local version (1.0.0) matches latest release"
    And no branch should be created
    And no PR should be created

  Scenario: Upgrade fails with dirty working tree
    Given my local version is "0.9.0"
    And the latest upstream version is "1.0.0"
    And I have uncommitted changes
    When I run the upgrade command
    Then the upgrade should fail
    And I should see "Your working tree has uncommitted changes"
    And I should see instructions to commit or stash changes

  Scenario: Upgrade fails without GitHub authentication
    Given my local version is "0.9.0"
    And the latest upstream version is "1.0.0" 
    And my working tree is clean
    And GitHub CLI is not authenticated
    When I run the upgrade command
    Then the upgrade should fail
    And I should see "GitHub CLI is not authenticated"
    And I should see "gh auth login" instruction

  Scenario: Sync branch already exists
    Given my local version is "0.9.0"
    And the latest upstream version is "1.0.0"
    And a branch "agile-flow-sync/v1.0.0" already exists on remote
    When I run the upgrade command
    Then I should see "Branch agile-flow-sync/v1.0.0 already exists on remote"
    And I should see "Skipping PR creation"
    And no new PR should be created

  Scenario: Selective file synchronization
    Given my local version is "0.9.0" 
    And the latest upstream version is "1.0.0"
    And syncDirectories contains ".claude/agents" and "scripts"
    And upstream has changes in ".claude/agents/worker.md" and "app/main.py"
    When I run the upgrade command
    Then ".claude/agents/worker.md" should be updated
    And "app/main.py" should not be touched
    And I should see "UPDATED: .claude/agents/worker.md"
    And I should not see any messages about "app/main.py"