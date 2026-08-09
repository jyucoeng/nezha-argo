#!/usr/bin/env bash

# vacuum.sh 定时压缩 sqlite 数据库瘦身，仅在数据库超过阈值时短暂停面板执行 VACUUM

DB=
VACUUM_MIN_SIZE=52428800

########

# version: 2026.08.09

# 数据库未超过阈值时直接跳过，避免无意义的停机
SIZE=$(stat -c%s "$DB" 2>/dev/null || echo 0)
[ "$SIZE" -lt "$VACUUM_MIN_SIZE" ] && exit 0

# 短暂停面板压缩数据库，压缩完成后立即恢复；即使 VACUUM 失败也会恢复面板
supervisorctl stop nezha >/dev/null 2>&1
sqlite3 "$DB" 'VACUUM;'
supervisorctl start nezha >/dev/null 2>&1
