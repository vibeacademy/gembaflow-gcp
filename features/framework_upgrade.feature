Feature: Framework Upgrade 
  As a developer using an Agile Flow fork
  I want to upgrade my framework files from upstream releases
  So that I can get the latest bug fixes and features without losing my project-specific changes

  Background:
    Given I am in an Agile Flow project directory
    And I have a valid ".agile-flow-version" file with version, upstream, and syncDirectories
    And I have git configured with appropriate credentials
    And I am in a GitHub Actions environment or have gh CLI configured

  Scenario: No updates available
    Given my local version matches the latest upstream release
    When the template sync script runs
    Then it should fetch the latest release from the upstream repository
    And it should compare my local version with the latest version
    And it should output "No updates available"
    And it should exit with code 0
    And no new branches or PRs should be created

  Scenario: Update available and sync succeeds
    Given there is a newer version available upstream
    And the upstream release contains files matching my syncDirectories
    When the template sync script runs
    Then it should download the release tarball from GitHub
    And it should extract the tarball to a temporary directory
    And it should sync each directory/file listed in syncDirectories
    And it should create a new branch named "agile-flow-sync/v{version}"
    And it should update the version in ".agile-flow-version"
    And it should commit changes with message "chore(sync): update Agile Flow framework to v{version}"
    And it should push the branch to origin
    And it should create a PR with title "chore(sync): update Agile Flow framework to v{version}"
    And the PR body should list all updated files
    And the PR body should include a link to the release notes
    And it should output "PR created successfully"

  Scenario: Sync with no file changes
    Given there is a newer version available upstream
    But all syncDirectories files already match the upstream version
    When the template sync script runs
    Then it should download and process the upstream files
    And it should detect that no files need updating
    And it should output "Already up to date"
    And it should exit with code 0
    And no branches or PRs should be created

  Scenario: Branch already exists for version
    Given there is a newer version available upstream
    And a branch "agile-flow-sync/v{version}" already exists on remote
    When the template sync script runs
    Then it should detect the existing branch
    And it should output "Branch already exists on remote"
    And it should skip PR creation
    And it should exit with code 0

  Scenario: Upstream repository is unreachable
    Given the upstream repository URL is invalid or unreachable
    When the template sync script runs
    Then it should fail to fetch the latest release
    And it should output an error about fetching from upstream
    And it should exit with code 1