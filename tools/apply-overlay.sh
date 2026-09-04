#!/bin/bash

# Materialize the Antharchy source tree: fetch the pinned Omarchy commit,
# apply the overlay to it, and leave a complete tree the PKGBUILDs can package.
#
# This is the ONLY way a tree is ever produced. The PKGBUILDs call it, CI calls
# it, and developers call it. There is deliberately no second code path that
# could drift from this one.
#
# Phase order matters: patches apply to the PRISTINE upstream tree, never to
# overlay output. A patch that expected upstream context but got ours would
# apply cleanly and mean something different.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEST="$ROOT/build/src"
CACHE="${ANTHARCHY_CACHE:-$ROOT/build/cache}"
CHECK_ONLY=0
COMMIT_OVERRIDE=""
UPSTREAM_TREE=""

die() { echo "apply-overlay: $*" >&2; exit 1; }
note() { echo "  $*"; }
phase() { echo; echo "── $* ──"; }

usage() {
  cat <<'USAGE'
Usage: tools/apply-overlay.sh [options]

  --into <dir>       Where to materialize the tree (default: build/src)
  --upstream <dir>   Use an existing pristine checkout instead of fetching
  --commit <sha>     Override upstream.lock's pin (for bump validation)
  --check            Validate only: assert the manifests and dry-run every
                     patch. Writes nothing. Used by CI and bump-upstream.sh.
  -h, --help         This message
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --into) DEST="$2"; shift 2 ;;
    --upstream) UPSTREAM_TREE="$2"; shift 2 ;;
    --commit) COMMIT_OVERRIDE="$2"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

# ── 1. resolve ───────────────────────────────────────────────────────────────
# Read the pin. `source` rather than a parser: upstream.lock is deliberately
# plain KEY=value so both bash and the PKGBUILDs can read it the same way.

phase "resolve"

[[ -f $ROOT/upstream.lock ]] || die "no upstream.lock at $ROOT"
# shellcheck source=/dev/null
source "$ROOT/upstream.lock"

commit="${COMMIT_OVERRIDE:-$OMARCHY_COMMIT}"
[[ $commit =~ ^[0-9a-f]{40}$ ]] || die "OMARCHY_COMMIT must be a full 40-char sha, got: $commit"

if [[ -n $UPSTREAM_TREE ]]; then
  [[ -d $UPSTREAM_TREE ]] || die "--upstream $UPSTREAM_TREE is not a directory"
  pristine="$UPSTREAM_TREE"
  note "using existing checkout $pristine"
else
  pristine="$CACHE/omarchy-$commit"
  if [[ -d $pristine/.git ]]; then
    note "cache hit $commit"
  else
    note "fetching $commit from $OMARCHY_REPO"
    rm -rf "$pristine"
    mkdir -p "$pristine"
    git -C "$pristine" init -q .
    git -C "$pristine" remote add origin "$OMARCHY_REPO"
    git -C "$pristine" fetch -q --depth 1 origin "$commit" ||
      die "could not fetch $commit -- is the pin reachable?"
    git -C "$pristine" checkout -q FETCH_HEAD
  fi

  # Verify we got the commit we asked for. A fetch that silently resolved to
  # something else would poison every downstream build.
  got=$(git -C "$pristine" rev-parse HEAD)
  [[ $got == "$commit" ]] || die "expected $commit but checkout is at $got"
fi

note "upstream tree: $pristine"

# ── 2. lint ──────────────────────────────────────────────────────────────────
# Cross-check the three manifests against each other before touching anything.
# A path claimed by two mechanisms is always a mistake, and the resulting tree
# would depend on phase order rather than on intent.

phase "lint"

overlay_paths=$(cd "$ROOT/overlay" && find . -type f -o -type l | sed 's|^\./||' | sort)
map_paths=$(grep -vE '^\s*(#|$)' "$ROOT/overlay.map" | sed -E 's/^[[:space:]]*[a-z]+[[:space:]]+//' | sort)
delete_paths=$(grep -vE '^\s*(#|$)' "$ROOT/delete.list" | sort)

# Every overlay file needs a classification, and every classification needs a
# file. Without both directions an overlay file can ship unclassified (so its
# pre-existence is never asserted) or a stale row can outlive its file.
if ! diff_out=$(diff <(echo "$overlay_paths") <(echo "$map_paths")); then
  echo "$diff_out" >&2
  die "overlay/ and overlay.map disagree (< only in overlay/, > only in overlay.map)"
fi
note "overlay.map covers $(echo "$map_paths" | grep -c .) path(s)"

patch_targets=""
while read -r patch; do
  [[ -n $patch ]] || continue
  [[ -f $ROOT/patches/$patch ]] || die "patches/series lists $patch, which does not exist"
  targets=$(grep -E '^--- a/' "$ROOT/patches/$patch" | sed 's|^--- a/||')
  patch_targets+="$targets"$'\n'
done < <(grep -vE '^\s*(#|$)' "$ROOT/patches/series")
patch_targets=$(echo "$patch_targets" | grep -v '^$' | sort -u)
note "patches touch $(echo "$patch_targets" | grep -c .) file(s)"

while IFS= read -r path; do
  [[ -n $path ]] || continue
  grep -qxF "$path" <<<"$patch_targets" && die "$path is both patched and deleted"
  grep -qxF "$path" <<<"$map_paths" && die "$path is both overlaid and deleted"
done <<<"$delete_paths"
while IFS= read -r path; do
  [[ -n $path ]] || continue
  grep -qxF "$path" <<<"$patch_targets" &&
    die "$path is both patched and overlaid -- promote it to overlay-only"
done <<<"$map_paths"
note "no path is claimed twice"

# ── 3. assert ────────────────────────────────────────────────────────────────
# The manifests describe upstream as we believe it to be. Check that belief
# against the tree we actually fetched. This is what turns overlay/ into a
# drift detector rather than a pile of files that always "works".

phase "assert"

fail=0
while read -r mode path; do
  [[ -n ${mode:-} ]] || continue
  case "$mode" in
    replace)
      # We are overriding an upstream file. If it is gone, upstream renamed or
      # deleted it and our override is now dead weight nobody would notice.
      [[ -e $pristine/$path ]] ||
        { echo "  MISSING  replace $path -- not in upstream $commit" >&2; fail=1; }
      ;;
    new)
      # We are adding a file. If upstream now ships one at the same path, a
      # plain copy would silently clobber it.
      [[ -e $pristine/$path ]] &&
        { echo "  COLLIDES new $path -- upstream $commit now ships this" >&2; fail=1; }
      ;;
    *) die "overlay.map: unknown mode '$mode' for $path (want replace|new)" ;;
  esac
done < <(grep -vE '^\s*(#|$)' "$ROOT/overlay.map")

while IFS= read -r path; do
  [[ -n $path ]] || continue
  [[ -e $pristine/$path ]] ||
    { echo "  MISSING  delete $path -- upstream already removed it" >&2; fail=1; }
done <<<"$delete_paths"

(( fail == 0 )) || die "manifest assertions failed against upstream $commit"
note "all manifest assertions hold"

# ── 4. patch (dry run first) ─────────────────────────────────────────────────

phase "patch"

if (( CHECK_ONLY )); then
  # --check never writes, so dry-run against the pristine tree itself.
  ok=1
  while read -r patch; do
    [[ -n $patch ]] || continue
    if git -C "$pristine" apply --check --whitespace=error "$ROOT/patches/$patch" 2>&1; then
      note "ok       $patch"
    else
      echo "  FAILED   $patch" >&2
      ok=0
    fi
  done < <(grep -vE '^\s*(#|$)' "$ROOT/patches/series")
  (( ok )) || die "one or more patches no longer apply to upstream $commit"
  echo
  echo "check passed: overlay applies cleanly to omarchy $commit"
  exit 0
fi

# ── materialize ──────────────────────────────────────────────────────────────

phase "materialize"

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
# -a preserves the symlinks in bin/ and the exec bits the package relies on.
# .git is excluded: the materialized tree is a build artifact, and shipping a
# git dir inside it would make omarchy-version report a dev checkout.
rsync -a --exclude '.git' "$pristine/" "$DEST/"
note "copied upstream into $DEST"

while read -r patch; do
  [[ -n $patch ]] || continue
  # Applied from inside the tree rather than with --directory, which takes a
  # repo-relative path and rejects an absolute one.
  #
  # GIT_CEILING_DIRECTORIES is load-bearing, not defensive. The default
  # materialization target lives under the overlay repo, so without it `git
  # apply` discovers THIS repository, resolves the patch paths against its
  # root instead of the tree, finds nothing to touch, ignores every hunk --
  # and exits 0. Every patch reports success and none of them apply.
  ( cd "$DEST" && GIT_CEILING_DIRECTORIES="$(dirname "$DEST")" \
      git apply --whitespace=error "$ROOT/patches/$patch" ) ||
    die "patch $patch failed against the materialized tree (it passed --check?)"
  note "applied  $patch"
done < <(grep -vE '^\s*(#|$)' "$ROOT/patches/series")

# Every patched file must now actually differ from upstream. `git apply` can
# report success while changing nothing -- that is exactly what a repo-context
# mix-up does -- so success is verified against the tree rather than trusted
# from an exit code.
while IFS= read -r path; do
  [[ -n $path ]] || continue
  if cmp -s "$pristine/$path" "$DEST/$path"; then
    die "patched file $path is byte-identical to upstream: the patch was silently ignored"
  fi
done <<<"$patch_targets"
note "verified $(echo "$patch_targets" | grep -c .) patched file(s) differ from upstream"

while IFS= read -r path; do
  [[ -n $path ]] || continue
  rm -rf "${DEST:?}/$path"
  note "deleted  $path"
done <<<"$delete_paths"

rsync -a "$ROOT/overlay/" "$DEST/"
note "overlaid $(echo "$map_paths" | grep -c .) file(s)"

# ── substitute ───────────────────────────────────────────────────────────────
# Overlay files carry @@TOKEN@@ placeholders for project constants so the
# domain, key fingerprint and URLs have exactly one definition. Substitute
# them into the materialized tree, then fail on any that did not resolve --
# an unresolved placeholder shipped to users is worse than a build error.

# shellcheck source=/dev/null
source "$ROOT/project.conf"

# Scoped to the paths WE ship, never the whole tree. Upstream has its own
# @@TOKEN@@ templates -- default/limine/default.conf carries @@CMDLINE@@ for
# the ISO to substitute at install time -- and rewriting or erroring on those
# would corrupt files we do not own.
subst_targets=$(while IFS= read -r rel; do
  [[ -n $rel ]] || continue
  [[ -f $DEST/$rel ]] || continue
  if grep -qE '@@[A-Z_]+@@' "$DEST/$rel" 2>/dev/null; then
    echo "$rel"
  fi
done <<<"$map_paths")

if [[ -n $subst_targets ]]; then
  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    while read -r var; do
      [[ -n $var ]] || continue
      token="@@${var}@@"
      # ${!var} is an indirect expansion: the value of the variable named $var.
      value="${!var-}"
      [[ -n $value ]] || die "$rel uses $token but project.conf does not define $var"
      python3 - "$DEST/$rel" "$token" "$value" <<'PY'
import io, sys
path, token, value = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(path, encoding='utf-8').read()
io.open(path, 'w', encoding='utf-8').write(s.replace(token, value))
PY
    done < <(grep -oE '@@[A-Z_]+@@' "$DEST/$rel" | tr -d '@' | sort -u)
    note "resolved  $rel"
  done <<<"$subst_targets"
fi

leftover=$(while IFS= read -r rel; do
  [[ -n $rel ]] || continue
  [[ -f $DEST/$rel ]] || continue
  if grep -qE '@@[A-Z_]+@@' "$DEST/$rel" 2>/dev/null; then
    echo "  $rel"
  fi
done <<<"$map_paths")
[[ -z $leftover ]] || die "unresolved placeholders remain in:"$'\n'"$leftover"

# ── 7. stamp ─────────────────────────────────────────────────────────────────
# Recorded so a running system can say exactly what it was built from. The
# PKGBUILDs install this; omarchy-version reads OMARCHY_VERSION from it.

cat > "$DEST/.antharchy-provenance" <<PROV
omarchy_repo=$OMARCHY_REPO
omarchy_commit=$commit
omarchy_tag=${OMARCHY_TAG:-}
omarchy_version=$OMARCHY_VERSION
antharchy_release=$ANTHARCHY_RELEASE
overlay_commit=$(git -C "$ROOT" rev-parse --verify --quiet HEAD || echo unknown)
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROV
note "stamped .antharchy-provenance"

# ── 8. scan ──────────────────────────────────────────────────────────────────

phase "scan"
"$ROOT/tools/verify-overlay.sh" "$DEST"

echo
echo "materialized omarchy $commit + overlay into $DEST"
