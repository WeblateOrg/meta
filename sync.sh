#!/bin/bash

# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: CC0-1.0

set -u -e

SYNC_BRANCH="weblate-meta-sync"
SYNC_COMMIT_MESSAGE="chore: sync with WeblateOrg/meta"
SYNC_PR_TITLE="$SYNC_COMMIT_MESSAGE"
SYNC_PR_BODY="Automated sync with WeblateOrg/meta."

REPOS="
    customize-example
    wlc
    scripts
    weblate
    website
    weblate_schemas
    translation-finder
    munin
    fail2ban
    docker
    docker-base
    docker-dev
    docker-compose
    hosted wllegal
    language-data
    graphics
    helm
    fonts
    siphashc
    openshift
    kotlin-sdk
    unicode-segmentation-rs
    .github
"

# Copy the files to all repos if not present, these are expected to diverge
INITFILES="
    .pre-commit-config.yaml
    .github/renovate.json
"

# Copy these files unconditionally
COPYFILES="
    .github/workflows/pre-commit.yml
    .github/actions/pre-commit-setup/action.yml
    .github/workflows/pull_requests.yaml
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
"

if [ ! -f .venv/bin/activate ]; then
    echo "Missing virtualenv in .venv!"
    exit 1
fi

# shellcheck disable=SC1091
. .venv/bin/activate

export ROOT="$PWD"

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

default_branch() {
    local branch

    if ! branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD); then
        echo "Could not determine default branch for $(basename "$PWD")" >&2
        exit 1
    fi

    echo "${branch#origin/}"
}

sync_pr_url() {
    gh pr list --head "$SYNC_BRANCH" --state open --json url --jq '.[0].url // ""'
}

push_sync_pr() {
    local default_branch
    local pr_url

    default_branch=$1

    git push --force-with-lease origin "$SYNC_BRANCH"

    pr_url=$(sync_pr_url)
    if [ -z "$pr_url" ]; then
        gh pr create --base "$default_branch" --head "$SYNC_BRANCH" --title "$SYNC_PR_TITLE" --body "$SYNC_PR_BODY"
        pr_url=$(sync_pr_url)
    else
        echo "Updating existing pull request: $pr_url"
    fi

    if [ -z "$pr_url" ]; then
        echo "Could not find sync pull request for $(basename "$PWD")" >&2
        exit 1
    fi

    gh pr merge "$pr_url" --auto --rebase
}

for repo in $REPOS; do
    if [ ! -d "$repo" ]; then
        git clone "git@github.com:WeblateOrg/$repo.git"
    fi
    cd "$repo"
    git fetch --quiet --prune origin
    DEFAULT_BRANCH=$(default_branch)
    git reset --quiet --hard
    git checkout --quiet -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
    git checkout --quiet -B "$SYNC_BRANCH" "$DEFAULT_BRANCH"

    echo "== $repo =="

    # Check README
    if ! grep -q Logo-Darktext-borders.png README.* 2> /dev/null; then
        echo "WARNING: README does not containing logo."
    fi

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
        push_sync_pr "$DEFAULT_BRANCH"
    fi

    echo
    cd ..
done
