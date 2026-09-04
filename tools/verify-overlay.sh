#!/bin/bash

# Scan a materialized tree for upstream identity that should not have survived
# the overlay.
#
# This is the second net. `git apply` catches syntactic drift -- a patch whose
# context moved. It cannot catch semantic drift: upstream adding a *new*
# app.hey.com reference in a *new* file, where every patch still applies and
# Antharchy silently ships a HEY binding again. Only a scan of the finished
# tree catches that.

set -euo pipefail

DEST="${1:-}"
[[ -n $DEST && -d $DEST ]] || { echo "usage: verify-overlay.sh <materialized-tree>" >&2; exit 2; }

# Paths that legitimately mention upstream and are exempt.
#
# omarchy-upgrade-to-quattro migrates an Omarchy 3 install to 4. It is
# referenced by ten files under test/shell.d/, so removing it costs ten test
# patches with permanent drift exposure -- to delete a script that only runs
# when a human explicitly invokes it from an Omarchy 3 system, which no
# Antharchy system will ever be. It keeps its upstream references.
#
# agents/skills and default/agents/skills are contributor documentation that
# correctly points at upstream's issue tracker and Discord.
# Two upstream migrations are exempted by exact path rather than by exempting
# migrations/ wholesale, so a FUTURE migration that references upstream still
# fails the build. Both are inert on Antharchy: each is guarded on state that
# only an Omarchy system has, and a fresh install never runs either, because
# antharchy-settings pre-seeds every migration marker into /etc/skel.
#
#   1787589206  drops a `SigLevel = Optional TrustAll` override from an
#               [omarchy] repo stanza we never ship.
#   1788112314  repoints an [omarchy] Server line, guarded on
#               rc-mirror.omarchy.org appearing in the mirrorlist. Ours is
#               Arch Linux ARM.
EXEMPT=(
  'bin/omarchy-upgrade-to-quattro'
  'test/shell.d/launcher-remove-test.sh'
  'test/shell.d/upgrade-to-quattro-test.sh'
  'test/shell.d/tailscale-test.sh'
  'migrations/1787589206.sh'
  'migrations/1788112314.sh'
  'default/agents/skills/'
  'agents/skills/'
  'manual/'
  # docs/ and plans/ are upstream's own contributor documentation and ship in
  # no package; docs/file-layout.md legitimately describes the HEY launcher as
  # part of upstream's install map.
  'docs/'
  'plans/'
  '.antharchy-provenance'
)

# Each entry is a literal string that must not appear in the shipped tree.
FORBIDDEN=(
  'app.hey.com'
  'HEY.desktop'
  'basecamp/hey-cli'
  'Basecamp'
  '37signals'
  'pkgs.omarchy.org'
  'stable-mirror.omarchy.org'
  'rc-mirror.omarchy.org'
  '40DFB630FF42BCFFB047046CF0134EE680CAC571'
  'Omarchy $version'
)

is_exempt() {
  local path="$1" ex
  for ex in "${EXEMPT[@]}"; do
    [[ $path == *"$ex"* ]] && return 0
  done
  return 1
}

fail=0
for needle in "${FORBIDDEN[@]}"; do
  hits=""
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    rel="${path#"$DEST"/}"
    is_exempt "$rel" && continue
    hits+="    $rel"$'\n'
  done < <(grep -rlF --binary-files=without-match -- "$needle" "$DEST" 2>/dev/null || true)

  if [[ -n $hits ]]; then
    echo "  FORBIDDEN  '$needle' survives in:" >&2
    printf '%s' "$hits" >&2
    fail=1
  fi
done

if (( fail )); then
  echo >&2
  echo "The overlay let upstream identity through. Either extend the overlay to" >&2
  echo "cover the new reference, or add a deliberate exemption to EXEMPT in" >&2
  echo "tools/verify-overlay.sh with a comment saying why." >&2
  exit 1
fi

echo "  scan clean: no forbidden upstream identity in $DEST"
