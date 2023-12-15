#!/bin/sh

# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: CC0-1.0

set -u -e

REPOS="
    customize-example
    wlc
    scripts
    fedora_messaging
    weblate
    website
    weblate_schemas
    translation-finder
    munin
    fail2ban
    docker
    docker-compose
    hosted wllegal
    language-data
    graphics
    helm
    siphashc
    openshift
    locale_lint
    .github
"

# Copy the files to all repos if not present, these are expected to diverge
INITFILES="
    .pre-commit-config.yaml
"

# Copy these files unconditionally
COPYFILES="
    .github/renovate.json
    .github/labels.yml
    .github/workflows/closing.yml
    .github/workflows/labels.yml
    .github/workflows/label-sync.yml
    .github/workflows/pre-commit.yml
    .github/workflows/pull_requests.yaml
    .github/FUNDING.yml
    .yamllint.yml
    SECURITY.md
    .github/PULL_REQUEST_TEMPLATE.md
    .markdownlint.yml
    .github/workflows/stale.yml
    .github/ISSUE_TEMPLATE/bug_report.yml
    .github/ISSUE_TEMPLATE/feature_request.yml
"

# Update these files if present
PRESENTFILES="
    .github/workflows/super-linter.yml
    .github/matchers/sphinx-linkcheck.json
    .github/matchers/sphinx-linkcheck-warn.json
    .github/matchers/sphinx.json
    .github/workflows/yarn-update.yml
    .eslintrc.yml
    .stylelintrc
"

# Files to remove
REMOVEFILES="
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
"

if [ ! -f .venv/bin/activate ] ; then
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
    if [ ! -d "$dir" ] ; then
        mkdir -p "$dir"
    fi
    if [ -f "../../${file%.*}.$repo.${file##*.}" ] ; then
        cp "../../${file%.*}.$repo.${file##*.}" "$file"
    elif [ -f "../../$file.$repo" ] ; then
        cp "../../$file.$repo" "$file"
    else
        cp "../../$file" "$file"
    fi
    if [ -f "../../$file.license" ] ; then
        cp "../../$file.license" "$file.license"
    elif [ -f  "$file.license" ] ; then
        rm  "$file.license"
    fi
}

for repo in $REPOS ; do
    if [ ! -d "$repo" ] ; then
        git clone "git@github.com:WeblateOrg/$repo.git"
        cd "$repo"
    else
        cd "$repo"
        git reset --quiet --hard origin/HEAD
        git pull --quiet
    fi
    echo "== $repo =="

    # Check README
    if ! grep -q Logo-Darktext-borders.png README.* 2>/dev/null ; then
        echo "WARNING: README does not containing logo."
    fi

    # Update files
    mkdir -p .github/workflows/
    for file in $INITFILES ; do
        if [ ! -f "$file" ] ; then
            copyfile "$file" "$repo"
        fi
    done
    for file in $COPYFILES ; do
        copyfile "$file" "$repo"
    done
    for file in $PRESENTFILES ; do
        if [ -f "$file" ] ; then
            copyfile "$file" "$repo"
        fi
    done
    for file in $REMOVEFILES ; do
        if [ -f "$file" ] ; then
            rm "$file"
        fi
    done

    # Apply fixes
    "$ROOT/repo-fixups"

    # Update issue templates
    "$ROOT/update-issue-config" "$ROOT"

    # Add and push
    git add .
    if ! git diff --cached --exit-code ; then
        git commit -m 'Sync with WeblateOrg/meta'
        git push
    fi

    echo
    cd ..
done
