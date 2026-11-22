#!/usr/bin/env bash
# Tags: no-fasttest
# ^ cas is an object-storage metadata type; keep it off the minimal fasttest image.

# `system.cas_mounts.server_uuid` of this server's own mount equals `serverUUID()`, the content of the uuid file.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

DISK="${CLICKHOUSE_DATABASE}_05487_cas_mounts_server_uuid"

${CLICKHOUSE_CLIENT} --multiline -q """
DROP TABLE IF EXISTS t_cas_mounts_server_uuid;

CREATE TABLE t_cas_mounts_server_uuid (a UInt64)
ENGINE = MergeTree ORDER BY a
SETTINGS disk = disk(
    type = object_storage,
    object_storage_type = local,
    metadata_type = cas,
    cas_server_root_id = '${CLICKHOUSE_DATABASE}_05487',
    name = '${DISK}',
    path = '${DISK}_pool/');

INSERT INTO t_cas_mounts_server_uuid VALUES (1);
"""

${CLICKHOUSE_CLIENT} -q "
SELECT count(), countIf(server_uuid = serverUUID())
FROM system.cas_mounts
WHERE disk LIKE '%${DISK}%' AND is_leader IS NOT NULL"

# SYNC: removes on a forgotten disk are no-ops, so the table must be gone before the disk is forgotten.
${CLICKHOUSE_CLIENT} -q "DROP TABLE t_cas_mounts_server_uuid SYNC" || {
    echo "DROP failed"; exit 1; }

# FORGET logs an operator WARNING that the harness would flag; silence it for this call only.
${CLICKHOUSE_CLIENT} --allow_repeated_settings --send_logs_level=fatal \
    --query "SYSTEM CAS FORGET '${DISK}'" || {
    echo "FORGET failed"; exit 1; }
