#!/bin/sh

REPOS="customize-example wlc scripts fedora_messaging weblate website weblate_schemas translation-finder munin fail2ban docker docker-compose hosted wllegal language-data"

mkdir -p repos
cd repos

for repo in $REPOS ; do
    if [ ! -d $repo ] ; then
        git clone git@github.com:WeblateOrg/$repo.git
        cd $repo
    else
        cd $repo
        git pull -q
    fi
    echo "== $repo =="

    # Check README
    if ! grep -q Logo-Darktext-borders.png README.rst 2>/dev/null ; then
        echo "WARNING: README.rst not containing logo."
    fi

    echo
    cd ..
done
