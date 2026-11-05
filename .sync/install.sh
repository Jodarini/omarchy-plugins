#!/bin/bash
# Turn ~/.config/omarchy/plugins on this machine into a checkout of the
# omarchy-plugins repo, then switch on auto-sync.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Jodarini/omarchy-plugins/main/.sync/install.sh)
#
# Plugins already in the folder are left alone, except standalone copies of
# plugins this repo now carries: those are moved to a backup folder so the
# repo's version can take their place. Their ids don't change, so shell.json
# keeps them enabled exactly where they were.

set -euo pipefail

REPO="${OMARCHY_PLUGINS_REPO:-git@github.com:Jodarini/omarchy-plugins.git}"
DIR="$HOME/.config/omarchy/plugins"
BRANCH=main

export GIT_TERMINAL_PROMPT=0

mkdir -p "$DIR"

if [[ -d $DIR/.git ]]; then
  echo "$DIR is already a git checkout; skipping clone."
else
  git -C "$DIR" init --quiet -b "$BRANCH"
  git -C "$DIR" remote add origin "$REPO"
  if ! git -C "$DIR" fetch --quiet origin "$BRANCH"; then
    echo "Fetch over SSH failed; retrying over HTTPS."
    git -C "$DIR" remote set-url origin "https://github.com/Jodarini/omarchy-plugins.git"
    git -C "$DIR" fetch --quiet origin "$BRANCH"
  fi

  backup="$HOME/.config/omarchy/plugins.backup.$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r top; do
    [[ -e $DIR/$top || -L $DIR/$top ]] || continue
    mkdir -p "$backup"
    mv "$DIR/$top" "$backup/"
    echo "Moved existing $top to $backup/"
  done < <(git -C "$DIR" ls-tree --name-only "origin/$BRANCH")

  git -C "$DIR" checkout --quiet -b "$BRANCH" --track "origin/$BRANCH"
  echo "Checked out omarchy-plugins into $DIR"
fi

mkdir -p "$HOME/.local/bin"
ln -sfn "$DIR/.sync/omarchy-plugins" "$HOME/.local/bin/omarchy-plugins"
echo "Linked ~/.local/bin/omarchy-plugins"

"$HOME/.local/bin/omarchy-plugins" auto on

command -v omarchy-shell >/dev/null && omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

echo
echo "Done. Enable any plugin you haven't yet with: omarchy plugin enable <id>"
