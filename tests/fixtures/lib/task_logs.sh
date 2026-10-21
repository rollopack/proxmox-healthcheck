#!/usr/bin/env bash
#
# Fake vzdump task logs shared by the pvenode and pvesh fixtures.
#
# task_log_exists <profile> <upid>
#     Returns 0 when the profile has a log for the task.
# task_log_lines <profile> <upid> [start] [limit]
#     Prints the requested slice of the log (limit 0 means "to the end").

task_log_full() {
    local profile="$1" upid="$2"
    case "$profile:$upid" in
    stale:UPID:node:one,*)
        cat <<'OUT'
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
INFO: Finished Backup of VM 100 (00:00:08)
INFO: Backup finished at 2026-09-21 03:05:00
TASK OK
OUT
        ;;
    recent:UPID:node:recent)
        cat <<'OUT'
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
INFO: Finished Backup of VM 100 (00:00:08)
INFO: Starting Backup of VM 200 (lxc)
INFO: VM Name: ct01
INFO: Finished Backup of VM 200 (00:00:05)
INFO: Backup finished at 2026-10-20 03:10:00
TASK OK
OUT
        ;;
    failed:UPID:node:failed)
        cat <<'OUT'
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
ERROR: Backup of VM 100 failed - no space left on device
TASK ERROR: job failed
OUT
        ;;
    partial:UPID:node:partial-new)
        cat <<'OUT'
INFO: starting new backup job: vzdump 100 102 --compress zstd --storage NAS-NFS
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
INFO: Finished Backup of VM 100 (00:00:08)
INFO: Starting Backup of VM 102 (qemu)
INFO: VM Name: Danea
ERROR: Backup of VM 102 failed - no space left on device
TASK ERROR: job failed
OUT
        ;;
    partial:UPID:node:partial-old)
        cat <<'OUT'
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
INFO: Finished Backup of VM 100 (00:00:08)
INFO: Starting Backup of VM 102 (qemu)
INFO: VM Name: Danea
INFO: Finished Backup of VM 102 (00:00:15)
TASK OK
OUT
        ;;
    multi:UPID:node:multi)
        cat <<'OUT'
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
INFO: Finished Backup of VM 100 (00:00:08)
INFO: Starting Backup of VM 102 (qemu)
INFO: VM Name: Danea
INFO: Finished Backup of VM 102 (00:00:15)
INFO: Starting Backup of VM 103 (lxc)
INFO: VM Name: mailserver
INFO: Finished Backup of VM 103 (00:01:02)
TASK OK
OUT
        ;;
    quick:UPID:node:quick)
        cat <<'OUT'
INFO: starting new backup job: vzdump 100 102 --compress zstd --storage NAS-NFS --mode suspend
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
INFO: Finished Backup of VM 100 (00:00:08)
INFO: Starting Backup of VM 102 (qemu)
INFO: VM Name: Danea
INFO: Finished Backup of VM 102 (00:00:15)
TASK OK
OUT
        ;;
    paged:UPID:node:paged)
        cat <<'OUT'
INFO: Starting Backup of VM 100 (qemu)
INFO: VM Name: CHR
INFO: Finished Backup of VM 100 (00:00:08)
OUT
        awk 'BEGIN { for (i = 0; i < 1001; i++) print "INFO: finding dependent guests" }'
        cat <<'OUT'
INFO: Starting Backup of VM 105 (qemu)
INFO: VM Name: last
INFO: Finished Backup of VM 105 (00:00:01)
TASK OK
OUT
        ;;
    *)
        return 1
        ;;
    esac
}

task_log_exists() {
    task_log_full "$1" "$2" >/dev/null 2>&1
}

task_log_lines() {
    local profile="$1" upid="$2" start="${3:-0}" limit="${4:-0}"
    task_log_full "$profile" "$upid" \
        | awk -v start="$start" -v limit="$limit" 'NR > start && (limit <= 0 || NR <= start + limit)'
}
