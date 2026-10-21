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
    mkdir -p "$SANDBOX/lib"
    cp -f "$FIXTURES/lib"/* "$SANDBOX/lib/"
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
        PH_TEST_SMART="${PH_TEST_SMART:-sata-pe}" \
        PH_THRESH_SSD_PE_CYCLES="${PH_TEST_PE_RATING:-0}" \
        PH_TEST_VM_JSON="${PH_TEST_VM_JSON:-compact}" \
        PH_TEST_BACKUP="${PH_TEST_BACKUP:-empty}" \
        PH_TEST_LOG_SOURCE="${PH_TEST_LOG_SOURCE:-auto}" \
        PH_TEST_LOG_CALLS="$SANDBOX/log_calls" \
        PH_BACKUP_TASK_HISTORY="${PH_TEST_BACKUP_HISTORY:-30}" \
        PH_THRESH_BACKUP_AGE_DAYS="${PH_TEST_BACKUP_AGE_DAYS:-7}" \
        PH_SMART_SCAN_ALL_DISKS="${PH_TEST_SMART_SCAN_ALL_DISKS:-0}" \
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
scenario "storage.smart parses raw values with trailing text"
PH_TEST_SMART=sata-pe; PH_TEST_PE_RATING=0
make_bin; add_proxmox
run -c storage.smart
assert_rc 0
assert_contains "Power-on hours"
assert_matches "Temperature \\(C\\) +33$"
assert_not_contains "23/51"
assert_matches "Reallocated sectors +0"
assert_not_contains "device: /dev/sdb"

# ---------------------------------------------------------------------------
scenario "storage.smart does not warn on a vendor indicator contradicted by P/E counters"
PH_TEST_SMART=sata-pe; PH_TEST_PE_RATING=0
make_bin; add_proxmox
run -c storage.smart
assert_rc 0
assert_matches "Max P/E cycles +93"
assert_not_contains "below threshold"
assert_contains "set PH_THRESH_SSD_PE_CYCLES"

# ---------------------------------------------------------------------------
scenario "storage.smart warns from P/E counters when the rated endurance is set"
PH_TEST_SMART=sata-pe; PH_TEST_PE_RATING=100
make_bin; add_proxmox
run -c storage.smart
assert_rc 1
assert_contains "at 93.0% of rated 100"

# ---------------------------------------------------------------------------
scenario "storage.smart warns on a corroborated low wear indicator"
PH_TEST_SMART=sata-worn; PH_TEST_PE_RATING=0
make_bin; add_proxmox
run -c storage.smart
assert_rc 1
assert_contains "SSD remaining life 006% below threshold"

# ---------------------------------------------------------------------------
scenario "storage.smart reports an uncorroborated wear indicator without warning"
PH_TEST_SMART=sata-uncorroborated; PH_TEST_PE_RATING=0
make_bin; add_proxmox
run -c storage.smart
assert_rc 0
assert_contains "not flagged as worn"

# ---------------------------------------------------------------------------
scenario "storage.smart warns on explicit remaining-life attribute"
PH_TEST_SMART=sata-lifetime; PH_TEST_PE_RATING=0
make_bin; add_proxmox
run -c storage.smart
assert_rc 1
assert_contains "SSD life used 90% >= 80%"

# ---------------------------------------------------------------------------
scenario "storage.smart optionally scans physical disks outside ZFS pools"
PH_TEST_SMART=sata-pe; PH_TEST_PE_RATING=0; PH_TEST_SMART_SCAN_ALL_DISKS=1
make_bin; add_proxmox
run -c storage.smart
assert_rc 0
assert_contains "device: /dev/sdb"

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
scenario "--config loads the requested config before checks"
make_bin; add_proxmox
printf 'PH_THRESH_POOL_CAP_WARN=40\n' >"$SANDBOX/selected.conf"
run -c zfs.pool_health --config "$SANDBOX/selected.conf"
assert_rc 1
assert_contains "capacity 42% >= 40%"

# ---------------------------------------------------------------------------
scenario "--config fails clearly when the requested file is missing"
make_bin
run --config "$SANDBOX/missing.conf"
assert_rc 2
assert_contains "configuration file is not readable"

# ---------------------------------------------------------------------------
scenario "vm.usage parses pretty JSON and reports missing guest data"
PH_TEST_VM_JSON=pretty
make_bin; add_proxmox
run -c vm.usage
assert_rc 1
assert_contains "web01"
assert_contains "25.0%"
assert_contains "512/2048"
assert_contains "could not retrieve usage for 1 guest(s)"

# ---------------------------------------------------------------------------
scenario "backup.status warns when the latest successful backup is stale"
PH_TEST_BACKUP=stale
make_bin; add_proxmox
run -c backup.status
assert_rc 1
assert_contains "latest successful backup for VM/CT 100"
assert_contains "threshold"
assert_contains "UPID:node:one,},{two"

# ---------------------------------------------------------------------------
scenario "backup.status derives guests and names from the task log"
PH_TEST_BACKUP=recent
make_bin; add_proxmox
run -c backup.status
assert_rc 0
assert_contains "recent vzdump tasks completed successfully for 2 guest(s)"
assert_contains "200"
assert_contains "ct01"
assert_contains "lxc"
assert_not_contains "did not finish OK"

# ---------------------------------------------------------------------------
scenario "backup.status warns when no successful backup task exists"
PH_TEST_BACKUP=failed
make_bin; add_proxmox
run -c backup.status
assert_rc 1
assert_contains "no successful vzdump task found for VM/CT 100"

# ---------------------------------------------------------------------------
scenario "backup.status lists every guest of a multi-guest task"
PH_TEST_BACKUP=multi
make_bin; add_proxmox
run -c backup.status
assert_rc 0
assert_contains "100 CHR"
assert_contains "102 Danea"
assert_contains "103 mailserver"
assert_contains "Latest successful backup per guest"
assert_contains "GUEST COUNT"
assert_contains "  UPID: UPID:node:multi"
assert_not_contains "no vzdump task with a VM/CT id"

# ---------------------------------------------------------------------------
scenario "backup.status reports a guest that did not finish in the latest task"
PH_TEST_BACKUP=partial
make_bin; add_proxmox
: >"$SANDBOX/log_calls"
run -c backup.status
assert_rc 1
assert_contains "latest vzdump task for VM/CT 102 (Danea) did not finish OK"
assert_not_contains "for VM/CT 100"
if [ "$(wc -l <"$SANDBOX/log_calls")" -eq 2 ]; then
    t_pass "read only until both guests had a successful backup"
else
    t_fail "expected 2 task log reads, got $(wc -l <"$SANDBOX/log_calls")"
fi

# ---------------------------------------------------------------------------
scenario "backup.status falls back to node freshness when task logs are unreadable"
PH_TEST_BACKUP=nologs
make_bin; add_proxmox
run -c backup.status
assert_rc 0
assert_contains "per-guest backup attribution unavailable"
assert_contains "latest vzdump task completed successfully"
assert_not_contains "no vzdump task with a VM/CT id"
assert_not_contains "VM 100"

# ---------------------------------------------------------------------------
scenario "backup.status uses the task id when the log is unreadable"
PH_TEST_BACKUP=idonly
make_bin; add_proxmox
run -c backup.status
assert_rc 0
assert_contains "could not read the log of 1 task(s)"
assert_contains "recent vzdump tasks completed successfully for 1 guest(s)"

# ---------------------------------------------------------------------------
scenario "backup.status reads task logs through the pvesh JSON endpoint"
PH_TEST_BACKUP=multi
PH_TEST_LOG_SOURCE=pvesh
make_bin; add_proxmox
run -c backup.status
assert_rc 0
assert_contains "103 mailserver"
PH_TEST_LOG_SOURCE=auto

# ---------------------------------------------------------------------------
scenario "backup.status pages through long task logs"
PH_TEST_BACKUP=paged
make_bin; add_proxmox
run -c backup.status
assert_rc 0
assert_contains "100 CHR"
assert_contains "105 last"
assert_contains "2 guest(s)"

# ---------------------------------------------------------------------------
scenario "backup.status stops reading history after a complete recent job"
PH_TEST_BACKUP=quick
make_bin; add_proxmox
: >"$SANDBOX/log_calls"
run -c backup.status
assert_rc 0
assert_contains "recent vzdump tasks completed successfully for 2 guest(s)"
if [ "$(wc -l <"$SANDBOX/log_calls")" -eq 1 ]; then
    t_pass "read only the latest task log"
else
    t_fail "expected 1 task log read, got $(wc -l <"$SANDBOX/log_calls")"
fi

# ---------------------------------------------------------------------------
scenario "backup.status accepts a whitespace-formatted empty job list"
PH_TEST_BACKUP=empty-pretty
make_bin; add_proxmox
run -c backup.status
assert_rc 0
assert_contains "no backup job configured"

# ---------------------------------------------------------------------------
printf '\n------------------------------\n'
printf 'Tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
