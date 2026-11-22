#!/usr/bin/env bash
# Tags: no-fasttest
# no-fasttest: cas is an object-storage metadata type, absent from the fasttest image.

# `cas-fsck --partial` that is cut short by its deadline prints the partial summary and still exits 1 with
# TIMEOUT_EXCEEDED. The disk budgets one request attempt at 30 s, so `--timeout 1` leaves no room for any
# request and the deadline expires on the first one, whatever the pool size or the machine speed.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

DISK_NAME="ca_fsck_partial_${CLICKHOUSE_TEST_UNIQUE_NAME}_${RANDOM}"
POOL_DIR="${CLICKHOUSE_USER_FILES_UNIQUE}_fsck_partial_${RANDOM}"
rm -rf "${POOL_DIR:?}"
mkdir -p "${POOL_DIR}"
export TEST_DISK_05488_POOL="${POOL_DIR}/"
config="$CUR_DIR/05488_cas_fsck_partial_scan_exit_status.xml"

${CLICKHOUSE_CLIENT} --multiquery <<SQL
DROP TABLE IF EXISTS t_fsck_partial SYNC;
CREATE TABLE t_fsck_partial (k UInt64, v String)
ENGINE = MergeTree ORDER BY k
SETTINGS disk = disk(
    type = object_storage,
    object_storage_type = local,
    metadata_type = cas,
    cas_unsafe_remount_no_delay = 1,
    cas_server_root_id = '${CLICKHOUSE_DATABASE}_05488',
    name = '${DISK_NAME}',
    path = '${POOL_DIR}/',
    cas_gc_enabled = 0);
INSERT INTO t_fsck_partial SELECT number, toString(number) FROM numbers(1000);
SQL

OUT="${CLICKHOUSE_TMP}/${CLICKHOUSE_TEST_UNIQUE_NAME}_fsck.out"
ERR="${CLICKHOUSE_TMP}/${CLICKHOUSE_TEST_UNIQUE_NAME}_fsck.err"
# Prints "<label> <exit code> <summary lines> <summary lines with partial=1> <stderr lines with TIMEOUT_EXCEEDED>".
function fsck()
{
    local label="$1"
    shift
    clickhouse-disks -C "$config" --disk cas_ro_05488 --query "cas-fsck $*" > "$OUT" 2> "$ERR"
    local rc=$?
    echo "$label $rc $(grep -c 'reachable=' "$OUT") $(grep -c 'partial=1' "$OUT") $(grep -c 'TIMEOUT_EXCEEDED' "$ERR")"
}

fsck complete
fsck cut_partial --timeout 1 --partial
fsck cut_without_partial --timeout 1
rm -f "$OUT" "$ERR"

${CLICKHOUSE_CLIENT} --query "DROP TABLE t_fsck_partial SYNC"
${CLICKHOUSE_CLIENT} --allow_repeated_settings --send_logs_level=fatal --query "SYSTEM CAS FORGET '${DISK_NAME}'"
rm -rf "${POOL_DIR:?}"
