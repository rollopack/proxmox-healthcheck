#!/usr/bin/env bash
#
# Test harness for proxmox-healthcheck.
#
# Pure bash, no external test framework. It builds a throwaway sandbox with
# symlinks to the needed coreutils plus fake Proxmox/ZFS commands, then runs
# the script against controlled scenarios.
#
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SCRIPT="$ROOT/proxmox-healthcheck"
FIXTURES="$HERE/fixtures"

BASH_BIN=$(command -v bash)
ENV_BIN=$(command -v env)

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/phc-tests.XXXXXX")
BIN="$SANDBOX/bin"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0
fail=0
OUT=""
RC=0

make_bin() {
    rm -rf "$BIN"
    mkdir -p "$BIN"
    cp "$FIXTURES/base"/* "$BIN/"
    local t p
    for t in bash awk grep sed head tail sort cut tr paste date cat ls readlink uname \
             nproc free uptime hostname swapon env mkdir rm dirname basename wc id sleep; do
        [ -e "$BIN/$t" ] && continue
        p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$BIN/$t"
    done
    chmod +x "$BIN"/* 2>/dev/null || true
}

add_proxmox() {
    cp -f "$FIXTURES/bin"/* "$BIN/"
    chmod +x "$BIN"/* 2>/dev/null || true
}

run() {
    OUT=$("$ENV_BIN" -i \
        PATH="$BIN" \
        HOME="${HOME:-/tmp}" \
        PH_IO_SAMPLES=1 \
        PH_NET_INTERFACES=/nonexistent/ifaces \
        PH_ARCSTATS="$FIXTURES/arcstats" \
        PH_TEST_HEALTH="${PH_TEST_HEALTH:-ONLINE}" \
        PH_TEST_FRAG="${PH_TEST_FRAG:-5}" \
        PH_TEST_CAP="${PH_TEST_CAP:-42}" \
        PH_TEST_ERRORS="${PH_TEST_ERRORS:-No known data errors}" \
        "$BASH_BIN" "$SCRIPT" --no-color "$@" 2>&1)
    RC=$?
}

t_pass() { pass=$((pass + 1)); printf '  PASS  %s\n' "$1"; }
t_fail() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

assert_rc() {
    if [ "$RC" -eq "$1" ]; then
        t_pass "exit code == $1"
    else
        t_fail "expected exit code $1, got $RC"
        printf '%s\n' "$OUT" | sed 's/^/        | /'
    fi
}

assert_contains() {
    if printf '%s' "$OUT" | grep -qF -- "$1"; then
        t_pass "output contains: $1"
    else
        t_fail "output missing: $1"
    fi
}

assert_matches() {
    if printf '%s' "$OUT" | grep -qE -- "$1"; then
        t_pass "output matches: $1"
    else
        t_fail "output does not match: $1"
    fi
}

assert_not_contains() {
    if printf '%s' "$OUT" | grep -qF -- "$1"; then
        t_fail "output should not contain: $1"
    else
        t_pass "output does not contain: $1"
    fi
}

scenario() { printf '\n== %s\n' "$1"; }

# ---------------------------------------------------------------------------
scenario "healthy node"
PH_TEST_HEALTH=ONLINE; PH_TEST_FRAG=5; PH_TEST_CAP=42; PH_TEST_ERRORS="No known data errors"
make_bin; add_proxmox
run
assert_rc 0
assert_contains "Overall status: OK"
assert_contains "pool rpool is ONLINE"
assert_contains "Hit ratio"

# ---------------------------------------------------------------------------
scenario "degraded pool, high capacity and data errors"
PH_TEST_HEALTH=DEGRADED; PH_TEST_FRAG=60; PH_TEST_CAP=95; PH_TEST_ERRORS="1 data errors"
make_bin; add_proxmox
run
assert_rc 1
assert_contains "Overall status: CRITICAL"
assert_contains "health is DEGRADED"
assert_contains "capacity 95%"

# ---------------------------------------------------------------------------
scenario "fragmentation reported as '-' must not crash"
PH_TEST_HEALTH=ONLINE; PH_TEST_FRAG="-"; PH_TEST_CAP=42; PH_TEST_ERRORS="No known data errors"
make_bin; add_proxmox
run -c zfs.pool_health
assert_rc 0
assert_contains "Fragmentation"

# ---------------------------------------------------------------------------
scenario "storage.smart parses ATA temperature and wear data"
make_bin; add_proxmox
run -c storage.smart
assert_rc 0
assert_contains "Power-on hours"
assert_matches "Temperature \\(C\\) +40"
assert_matches "Reallocated sectors +0"

# ---------------------------------------------------------------------------
scenario "no Proxmox/ZFS tooling present"
make_bin
run
assert_rc 0
assert_contains "[skip] zpool not available"
assert_contains "Overall status: OK"

# ---------------------------------------------------------------------------
scenario "usage: --help"
make_bin
run --help
assert_rc 0
assert_contains "Usage:"

# ---------------------------------------------------------------------------
scenario "usage: unknown check id"
make_bin
run -c does.not.exist
assert_rc 2
assert_contains "unknown check"

# ---------------------------------------------------------------------------
printf '\n------------------------------\n'
printf 'Tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
