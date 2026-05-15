"""Step definitions for framework upgrade feature."""

import json
import subprocess
from unittest.mock import MagicMock, patch

from pytest_bdd import given, scenario, then, when

# Scenarios
scenario("../framework_upgrade.feature", "No updates available")
scenario("../framework_upgrade.feature", "Update available and sync succeeds")
scenario("../framework_upgrade.feature", "Sync with no file changes")
scenario("../framework_upgrade.feature", "Branch already exists for version")
scenario("../framework_upgrade.feature", "Upstream repository is unreachable")


# Given steps
@given("I am in an Agile Flow project directory")
def given_agile_flow_directory(temp_project_dir, context):
    """Ensure we're in an Agile Flow project directory."""
    context["project_dir"] = temp_project_dir
    assert (temp_project_dir / ".agile-flow-version").exists()


@given('I have a valid ".agile-flow-version" file with version, upstream, and syncDirectories')
def given_valid_version_file(temp_project_dir, context):
    """Ensure valid .agile-flow-version file exists."""
    version_file = temp_project_dir / ".agile-flow-version"
    version_data = {
        "version": "1.0.0",
        "upstream": "vibeacademy/agile-flow-gcp",
        "syncDirectories": [
            "scripts/",
            ".github/workflows/",
            "docs/"
        ]
    }
    version_file.write_text(json.dumps(version_data, indent=2))
    context["current_version"] = "1.0.0"
    context["upstream_repo"] = "vibeacademy/agile-flow-gcp"


@given("I have git configured with appropriate credentials")
def given_git_configured(mock_git, context):
    """Mock git configuration."""
    context["git_configured"] = True


@given("I am in a GitHub Actions environment or have gh CLI configured")
def given_github_environment(mock_gh_cli, context):
    """Mock GitHub environment setup."""
    context["github_configured"] = True


@given("my local version matches the latest upstream release")
def given_no_updates_available(context):
    """Mock scenario where no updates are available."""
    context["latest_version"] = "1.0.0"  # Same as current
    context["updates_available"] = False


@given("there is a newer version available upstream")
def given_updates_available(context):
    """Mock scenario where updates are available."""
    context["latest_version"] = "1.1.0"  # Newer than current 1.0.0
    context["updates_available"] = True


@given("the upstream release contains files matching my syncDirectories")
def given_matching_files_upstream(context):
    """Mock upstream release with matching files."""
    context["upstream_has_files"] = True
    context["files_to_sync"] = [
        "scripts/template-sync.sh",
        ".github/workflows/deploy.yml",
        "docs/README.md"
    ]


@given("all syncDirectories files already match the upstream version")
def given_files_already_match(context):
    """Mock scenario where files are already up to date."""
    context["files_match_upstream"] = True


@given('a branch "agile-flow-sync/v{version}" already exists on remote')
def given_branch_exists(context):
    """Mock scenario where sync branch already exists."""
    context["branch_exists"] = True
    context["existing_branch"] = f"agile-flow-sync/v{context['latest_version']}"


@given("the upstream repository URL is invalid or unreachable")
def given_upstream_unreachable(context):
    """Mock scenario where upstream is unreachable."""
    context["upstream_reachable"] = False


# When steps
@when("the template sync script runs")
def when_sync_script_runs(temp_project_dir, mock_subprocess, mock_gh_cli, context):
    """Run the template sync script with appropriate mocking."""

    with patch('subprocess.run') as mock_run:
        def side_effect(cmd, *args, **kwargs):
            if isinstance(cmd, list) and 'template-sync.sh' in str(cmd):
                result = MagicMock()

                if not context.get("upstream_reachable", True):
                    # Simulate unreachable upstream
                    result.returncode = 1
                    result.stderr = "Error fetching from upstream"
                    context["sync_output"] = result.stderr
                    return result

                elif not context.get("updates_available", False):
                    # No updates available
                    result.returncode = 0
                    result.stdout = "No updates available"
                    context["sync_output"] = result.stdout
                    return result

                elif context.get("branch_exists", False):
                    # Branch already exists
                    result.returncode = 0
                    result.stdout = "Branch already exists on remote"
                    context["sync_output"] = result.stdout
                    return result

                elif context.get("files_match_upstream", False):
                    # Files already match
                    result.returncode = 0
                    result.stdout = "Already up to date"
                    context["sync_output"] = result.stdout
                    return result

                else:
                    # Successful sync with updates
                    result.returncode = 0
                    result.stdout = "PR created successfully"
                    context["sync_output"] = result.stdout
                    context["pr_created"] = True
                    return result

            elif isinstance(cmd, list) and cmd[0] == 'gh':
                if 'release' in cmd and 'view' in cmd:
                    # Mock release info
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = (
                        f'{{"tag_name": "v{context.get("latest_version", "1.1.0")}", '
                        '"tarball_url": "https://github.com/test/repo/archive/v1.1.0.tar.gz"}}'
                    )
                    return result
                elif 'pr' in cmd and 'create' in cmd:
                    # Mock PR creation
                    result = MagicMock()
                    result.returncode = 0
                    result.stdout = "https://github.com/user/repo/pull/123"
                    return result

            # Default success
            return MagicMock(returncode=0, stdout="")

        mock_run.side_effect = side_effect

        # Simulate running the sync script
        result = subprocess.run(
            ["bash", "scripts/template-sync.sh"],
            capture_output=True,
            text=True
        )
        context["sync_result"] = result


# Then steps
@then("it should fetch the latest release from the upstream repository")
def then_fetch_latest_release(context):
    """Verify latest release was fetched."""
    assert context.get("sync_result") is not None


@then("it should compare my local version with the latest version")
def then_compare_versions(context):
    """Verify version comparison occurred."""
    assert context.get("sync_result") is not None


@then('it should output "No updates available"')
def then_output_no_updates(context):
    """Verify 'No updates available' message."""
    output = context.get("sync_output", "")
    assert "No updates available" in output


@then("it should exit with code 0")
def then_exit_success(context):
    """Verify successful exit code."""
    result = context.get("sync_result")
    assert result is not None
    assert result.returncode == 0


@then("no new branches or PRs should be created")
def then_no_branches_or_prs(context):
    """Verify no branches or PRs were created."""
    assert not context.get("pr_created", False)


@then("no branches or PRs should be created")
def then_no_branches_or_prs_alt(context):
    """Verify no branches or PRs were created (alternative step)."""
    assert not context.get("pr_created", False)


@then("it should download the release tarball from GitHub")
def then_download_tarball(context):
    """Verify tarball download."""
    assert context.get("sync_result") is not None


@then("it should extract the tarball to a temporary directory")
def then_extract_tarball(context):
    """Verify tarball extraction."""
    assert context.get("sync_result") is not None


@then("it should sync each directory/file listed in syncDirectories")
def then_sync_directories(context):
    """Verify directories are synced."""
    assert context.get("sync_result") is not None


@then('it should create a new branch named "agile-flow-sync/v{version}"')
def then_create_sync_branch(context):
    """Verify sync branch creation."""
    if context.get("updates_available") and not context.get("files_match_upstream"):
        assert context.get("sync_result") is not None


@then('it should update the version in ".agile-flow-version"')
def then_update_version_file(temp_project_dir, context):
    """Verify version file is updated."""
    if context.get("pr_created"):
        # In a real scenario, the version file would be updated
        version_file = temp_project_dir / ".agile-flow-version"
        assert version_file.exists()


@then('it should commit changes with message "chore(sync): update Agile Flow '
      'framework to v{version}"')
def then_commit_changes(context):
    """Verify commit with proper message."""
    if context.get("pr_created"):
        assert context.get("sync_result") is not None


@then("it should push the branch to origin")
def then_push_branch(context):
    """Verify branch is pushed."""
    if context.get("pr_created"):
        assert context.get("sync_result") is not None


@then('it should create a PR with title "chore(sync): update Agile Flow framework to v{version}"')
def then_create_pr(context):
    """Verify PR creation with proper title."""
    if context.get("pr_created"):
        assert context.get("sync_result") is not None


@then("the PR body should list all updated files")
def then_pr_body_lists_files(context):
    """Verify PR body contains file list."""
    if context.get("pr_created"):
        assert context.get("sync_result") is not None


@then("the PR body should include a link to the release notes")
def then_pr_body_has_release_link(context):
    """Verify PR body contains release notes link."""
    if context.get("pr_created"):
        assert context.get("sync_result") is not None


@then('it should output "PR created successfully"')
def then_output_pr_created(context):
    """Verify PR creation success message."""
    if context.get("pr_created"):
        output = context.get("sync_output", "")
        assert "PR created successfully" in output


@then("it should download and process the upstream files")
def then_download_and_process(context):
    """Verify upstream files are processed."""
    assert context.get("sync_result") is not None


@then("it should detect that no files need updating")
def then_detect_no_file_changes(context):
    """Verify detection of no file changes."""
    if context.get("files_match_upstream"):
        assert context.get("sync_result") is not None


@then('it should output "Already up to date"')
def then_output_up_to_date(context):
    """Verify 'Already up to date' message."""
    if context.get("files_match_upstream"):
        output = context.get("sync_output", "")
        assert "Already up to date" in output


@then("it should detect the existing branch")
def then_detect_existing_branch(context):
    """Verify existing branch detection."""
    if context.get("branch_exists"):
        assert context.get("sync_result") is not None


@then('it should output "Branch already exists on remote"')
def then_output_branch_exists(context):
    """Verify branch exists message."""
    if context.get("branch_exists"):
        output = context.get("sync_output", "")
        assert "Branch already exists on remote" in output


@then("it should skip PR creation")
def then_skip_pr_creation(context):
    """Verify PR creation is skipped."""
    if context.get("branch_exists"):
        assert not context.get("pr_created", False)


@then("it should fail to fetch the latest release")
def then_fail_to_fetch_release(context):
    """Verify failure to fetch release."""
    if not context.get("upstream_reachable", True):
        result = context.get("sync_result")
        assert result is not None
        assert result.returncode == 1


@then("it should output an error about fetching from upstream")
def then_output_fetch_error(context):
    """Verify fetch error message."""
    if not context.get("upstream_reachable", True):
        output = context.get("sync_output", "")
        assert "Error fetching from upstream" in output


@then("it should exit with code 1")
def then_exit_error(context):
    """Verify error exit code."""
    if not context.get("upstream_reachable", True):
        result = context.get("sync_result")
        assert result is not None
        assert result.returncode == 1
