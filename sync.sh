#!/bin/sh

set -u -e

REPOS="customize-example wlc scripts fedora_messaging weblate website weblate_schemas translation-finder munin fail2ban docker docker-compose hosted wllegal language-data graphics helm siphashc openshift"

INITFILES="requirements-lint.txt .pre-commit-config.yaml .github/dependabot.yml"
COPYFILES=".github/stale.yml .github/labels.yml .github/workflows/closing.yml .github/workflows/labels.yml .github/workflows/label-sync.yml .github/workflows/pre-commit.yml .github/workflows/pull_requests.yaml .github/FUNDING.yml .github/.kodiak.toml .yamllint.yml SECURITY.md .github/PULL_REQUEST_TEMPLATE.md .markdownlint.json"
PRESENTFILES=".github/workflows/super-linter.yml .github/matchers/sphinx-linkcheck.json .github/matchers/sphinx.json .github/matchers/flake8.json .github/matchers/eslint-compact.json .github/workflows/flake8.yml .github/workflows/eslint.yml .github/workflows/stylelint.yml .eslintrc.yml .stylelintrc"

if [ -f .venv/bin/activate ] ; then
    # shellcheck disable=SC1091
    . .venv/bin/activate
else
    echo "Missing virtualenv in .venv!"
    exit 1
fi

ROOT=$PWD

mkdir -p repos
cd repos

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
            cp "../../$file" "$file"
        fi
    done
    for file in $COPYFILES ; do
        cp "../../$file" "$file"
    done
    for file in $PRESENTFILES ; do
        if [ -f "$file" ] ; then
            cp "../../$file" "$file"
        fi
    done

    # Apply fixes
    "$ROOT/repo-fixups"

    # Pre-commit update
    pre-commit autoupdate

    # Generate dependabot configuration
    "$ROOT/generate-dependabot"

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
