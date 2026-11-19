#!/bin/bash

# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: CC0-1.0

set -u -e

SYNC_BRANCH="weblate-meta-sync"
SYNC_COMMIT_MESSAGE="chore: sync with WeblateOrg/meta"
SYNC_PR_TITLE="$SYNC_COMMIT_MESSAGE"
SYNC_PR_BODY="Automated sync with WeblateOrg/meta."

# Copy the files to all repos if not present, these are expected to diverge
INITFILES="
    .pre-commit-config.yaml
    .github/renovate.json
"

# Copy these files unconditionally
COPYFILES="
    .github/workflows/pre-commit.yml
    .github/actions/pre-commit-setup/action.yml
    .github/workflows/dependency-review.yml
    .github/FUNDING.yml
    .yamllint.yml
    .editorconfig
    SECURITY.md
    .github/PULL_REQUEST_TEMPLATE.md
    .github/ISSUE_TEMPLATE/bug_report.yml
    .github/ISSUE_TEMPLATE/feature_request.yml
"

# Automated comments
COMMENTFILES="
  .github/comments/issue-fixed.md
  .github/comments/issue-resolved.md
  .github/comments/issue-newbie.md
"
# Update these files if present
PRESENTFILES="
    .github/workflows/closing.yml
    .github/workflows/stale.yml
    .github/workflows/labels.yml
    .github/matchers/sphinx-linkcheck.json
    .github/matchers/sphinx-linkcheck-warn.json
    .github/matchers/sphinx.json
    .github/matchers/mypy.json
    .github/release.yml
    .eslintrc.yml
    .stylelintrc
    $COMMENTFILES
"

# Files to remove
REMOVEFILES="
    .markdownlint.yml
    .markdownlint.json
    .github/stale.yml
    .github/matchers/flake8.json
    .github/matchers/eslint-compact.json
    .github/matchers/flake8.json.license
    .github/matchers/eslint-compact.json.license
    .github/workflows/flake8.yml
    .github/ISSUE_TEMPLATE/bug_report.md
    .github/ISSUE_TEMPLATE/feature_request.md
    .github/ISSUE_TEMPLATE/support_question.md
    .github/ISSUE_TEMPLATE/support_question.yml
    .github/.kodiak.toml
    .github/workflows/ruff.yml
    .github/workflows/eslint.yml
    .github/workflows/stylelint.yml
    .github/workflows/codeql-analysis.yml
    .eslintrc.yml
    .github/labels.yml
    .github/workflows/label-sync.yml
    .github/workflows/pull_requests.yaml
"

if [ ! -f .venv/bin/activate ]; then
    echo "Missing virtualenv in .venv!"
    exit 1
fi

# shellcheck disable=SC1091
. .venv/bin/activate

export ROOT="$PWD"

# shellcheck disable=SC1091
. "$ROOT/repo-common.sh"

mkdir -p repos
cd repos

copyfile() {
    file=$1
    repo=$2
    dir=$(dirname "$file")
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
    if [ -f "../../${file%.*}.$repo.${file##*.}" ]; then
        cp "../../${file%.*}.$repo.${file##*.}" "$file"
    elif [ -f "../../$file.$repo" ]; then
        cp "../../$file.$repo" "$file"
    else
        cp "../../$file" "$file"
    fi
    if [ -f "../../$file.license" ]; then
        cp "../../$file.license" "$file.license"
    elif [ -f "$file.license" ]; then
        rm "$file.license"
    fi
}

sync_pr_number() {
    local repository=$1
    local default_branch=$2

    gh api --hostname github.com --method GET "repos/$repository/pulls" \
        -f state=open -f head="${repository%%/*}:$SYNC_BRANCH" -f base="$default_branch" \
        --jq '[.[] | select(.head.repo.full_name != null and .head.repo.full_name == .base.repo.full_name) | .number]
            | if length > 1 then error("Multiple matching sync pull requests") else .[0] // empty end'
}

push_sync_pr() {
    local repository=$1
    local default_branch=$2
    local sync_head
    local pr_number

    sync_head=$(git rev-parse HEAD)
    git push --force-with-lease origin "$sync_head:refs/heads/$SYNC_BRANCH"

    pr_number=$(sync_pr_number "$repository" "$default_branch")
    if [ -z "$pr_number" ]; then
        gh pr create --repo "github.com/$repository" --base "$default_branch" --head "$SYNC_BRANCH" --title "$SYNC_PR_TITLE" --body "$SYNC_PR_BODY"
        pr_number=$(sync_pr_number "$repository" "$default_branch")
    else
        echo "Updating existing pull request: https://github.com/$repository/pull/$pr_number"
    fi

    if [ -z "$pr_number" ]; then
        echo "Could not find sync pull request for $repository" >&2
        exit 1
    fi

    gh pr merge --repo "github.com/$repository" "$pr_number" --auto --rebase --match-head-commit "$sync_head"
}

for repo in $REPOS; do
    DEFAULT_BRANCH=$(prepare_repository "$repo")
    cd "$repo"
    git checkout --quiet -B "$SYNC_BRANCH" "$DEFAULT_BRANCH"

    echo "== $repo =="

    # Markdownling migration
    if [ -f .rumdl.toml ]; then
        if ! grep -q rumdl .pre-commit-config.yaml; then
            git rm .rumdl.toml
        elif [ -f pyproject.toml ]; then
            cat .rumdl.toml | grep -v '^#' | sed -e 's/^\[/[tool.rumdl./' -e s/tool.rumdl.global/tool.rumdl/ >> pyproject.toml
            git rm .rumdl.toml
        fi
    fi

    # Update files
    mkdir -p .github/workflows/
    for file in $INITFILES; do
        if [ ! -f "$file" ]; then
            copyfile "$file" "$repo"
        fi
    done
    for file in $COPYFILES; do
        copyfile "$file" "$repo"
    done
    for file in $PRESENTFILES; do
        if [ -f "$file" ]; then
            copyfile "$file" "$repo"
        fi
    done
    for file in $REMOVEFILES; do
        if [ -f "$file" ]; then
            rm "$file"
        fi
    done
    if [ -f .github/workflows/closing.yml ] || [ -f .github/workflows/labels.yml ]; then
        for file in $COMMENTFILES; do
            copyfile "$file" "$repo"
        done
    fi

    # Configure GitHub release notes generating
    if grep -q generateReleaseNotes .github/workflows/*; then
        copyfile ".github/release.yml" "$repo"
    fi

    # Apply fixes
    "$ROOT/repo-fixups"

    # Update issue templates
    "$ROOT/update-issue-config" "$ROOT"

    # Add and push pull request
    git add .
    if ! git diff --cached --exit-code; then
        git commit -m "$SYNC_COMMIT_MESSAGE"
        push_sync_pr "WeblateOrg/$repo" "$DEFAULT_BRANCH"
    fi

    echo
    cd ..
done
