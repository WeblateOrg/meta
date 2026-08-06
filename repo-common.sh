#!/bin/bash

# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: CC0-1.0

# Used by scripts sourcing this helper.
# shellcheck disable=SC2034
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

default_branch() {
    local branch
    local repo_path

    repo_path=$1
    if ! branch=$(git -C "$repo_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD); then
        echo "Could not determine default branch for $(basename "$repo_path")" >&2
        return 1
    fi

    echo "${branch#origin/}"
}

prepare_repository() {
    local branch
    local repo
    local repo_path

    repo=$1
    repo_path="$ROOT/repos/$repo"

    mkdir -p "$ROOT/repos"
    if [ ! -d "$repo_path" ]; then
        git clone "git@github.com:WeblateOrg/$repo.git" "$repo_path"
    fi

    git -C "$repo_path" fetch --quiet --prune origin
    branch=$(default_branch "$repo_path")
    git -C "$repo_path" reset --quiet --hard
    git -C "$repo_path" checkout --quiet -B "$branch" "origin/$branch"

    echo "$branch"
}
