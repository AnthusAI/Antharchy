#!/bin/bash

# Antharchy package identity.
#
# `pacman -Q` resolves real package names and never `provides`. Antharchy
# provides omarchy but is not named omarchy, so every upstream command that
# probes for the omarchy package finds nothing on an Antharchy system: no
# version, channel "unknown", and a SystemUpdate widget in the bar that stays
# dark because the checker it calls always reports "up to date".
#
# These four commands are the ones the overlay replaces for that reason, and
# this is the test that says so. It stubs pacman and /etc/pacman.conf rather
# than touching the host.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../shell.d/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Answers -Q / -Qq for whatever ANTHARCHY_TEST_PACKAGES lists, and nothing
# else -- which is exactly how a real pacman treats a `provides` name.
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
case "$1" in
  -Q | -Qq) ;;
  *) exit 1 ;;
esac
shift
for package in "$@"; do
  case ",${ANTHARCHY_TEST_PACKAGES:-}," in
    *",$package,"*) echo "$package ${ANTHARCHY_TEST_VERSION:-4.0.2-1}" ;;
    *) echo "error: package '$package' was not found" >&2; exit 1 ;;
  esac
done
exit 0
STUB
chmod +x "$stub_bin/pacman"

cat >"$stub_bin/checkupdates" <<'STUB'
#!/bin/bash
printf '%s\n' "${ANTHARCHY_TEST_UPDATES:-}"
STUB
chmod +x "$stub_bin/checkupdates"

run() {
  local command="$1"
  shift
  env "$@" PATH="$stub_bin:$PATH" "$ROOT/bin/$command"
}

# ── omarchy-version ──────────────────────────────────────────────────────────

installed="antharchy,antharchy-settings"

got=$(run omarchy-version ANTHARCHY_TEST_PACKAGES="$installed" OMARCHY_PATH=/usr/share/omarchy)
[[ $got == "4.0.2-1" ]] || fail "version reports the installed Antharchy package" "actual: $got"
pass "version reports the installed Antharchy package"

# The regression this whole override exists to prevent: upstream's version of
# this command queries `omarchy`, which is only ever a provides here.
if run omarchy-version ANTHARCHY_TEST_PACKAGES="omarchy,omarchy-settings" \
  OMARCHY_PATH=/usr/share/omarchy >/dev/null 2>&1; then
  fail "version does not resolve through the omarchy provides"
fi
pass "version does not resolve through the omarchy provides"

got=$(run omarchy-version ANTHARCHY_TEST_PACKAGES="" OMARCHY_PATH="$test_tmp/checkout" || true)
[[ $got == "dev" ]] || fail "version still reports a dev checkout" "actual: $got"
pass "version still reports a dev checkout"

# ── omarchy-version-channel ──────────────────────────────────────────────────

write_pacman_conf() {
  cat >"$test_tmp/pacman.conf" <<EOF
[options]
Architecture = auto

[extra]
Include = /etc/pacman.d/mirrorlist

[antharchy]
Server = https://antharchy.anthus.ai/$1/\$arch
EOF
}

# The channel lives in the [antharchy] Server line and nowhere else, so the
# parser is pointed at a stub conf rather than the host's.
channel_from_conf() {
  write_pacman_conf "$1"
  sed "s|/etc/pacman.conf|$test_tmp/pacman.conf|g" "$ROOT/bin/omarchy-version-channel" >"$test_tmp/version-channel"
  chmod +x "$test_tmp/version-channel"
  "$test_tmp/version-channel"
}

for channel in stable rc edge; do
  got=$(channel_from_conf "$channel")
  [[ $got == "$channel" ]] || fail "version-channel reads the $channel channel" "actual: $got"
done
pass "version-channel reads each channel from the [antharchy] repo"

# A conf with no [antharchy] repo is 'unknown', not a crash or a stale guess.
cat >"$test_tmp/pacman.conf" <<'EOF'
[options]
Architecture = auto
EOF
got=$("$test_tmp/version-channel")
[[ $got == "unknown" ]] || fail "version-channel reports unknown without an Antharchy repo" "actual: $got"
pass "version-channel reports unknown without an Antharchy repo"

# ── omarchy-update-available ─────────────────────────────────────────────────
# The bar's SystemUpdate widget calls this and believes it, so a false
# "up to date" is invisible rather than noisy.

set +e
out=$(run omarchy-update-available ANTHARCHY_TEST_PACKAGES="$installed" \
  ANTHARCHY_TEST_UPDATES="antharchy 4.0.2-1 -> 4.0.3-1" OMARCHY_PATH=/usr/share/omarchy 2>/dev/null)
status=$?
set -e
[[ $status -eq 0 ]] || fail "update-available exits 0 when an Antharchy update exists"
grep -q '^antharchy ' <<<"$out" || fail "update-available prints the Antharchy update" "actual: $out"
pass "update-available detects an Antharchy update"

set +e
out=$(run omarchy-update-available ANTHARCHY_TEST_PACKAGES="$installed" \
  ANTHARCHY_TEST_UPDATES="linux 6.1 -> 6.2" OMARCHY_PATH=/usr/share/omarchy 2>/dev/null)
status=$?
set -e
[[ $status -eq 1 ]] || fail "update-available exits 1 when only unrelated packages update"
[[ $out == "Antharchy is up to date" ]] || fail "update-available says Antharchy is up to date" "actual: $out"
pass "update-available ignores unrelated package updates"
