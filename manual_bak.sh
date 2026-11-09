#!/usr/bin/env bash

# manual_bak.sh - 手动备份哪吒面板数据到 GitHub 备份仓库（git push 方式，不依赖 wget 的 API 上传）
# 用法: bash manual_bak.sh
# 依赖: 容器内 /dashboard/backup.sh 已生成（内含 GH_PAT/GH_BACKUP_USER/GH_EMAIL/GH_REPO）
# 在线执行: bash <(wget -qO- https://raw.githubusercontent.com/jyucoeng/nezha-argo/main/manual_bak.sh)

set -e

WORK_DIR=${WORK_DIR:-/dashboard}
eval "$(grep -E '^GH_(PAT|BACKUP_USER|EMAIL|REPO)=' $WORK_DIR/backup.sh)"

for v in GH_PAT GH_BACKUP_USER GH_EMAIL GH_REPO; do
  [ -z "${!v}" ] && echo "Missing $v in $WORK_DIR/backup.sh" && exit 1
done

cd "$WORK_DIR"
TIME=$(date "+%Y-%m-%d-%H:%M:%S")
tar czf /tmp/dashboard-$TIME.tar.gz data/

cd /tmp
rm -rf nz_backup
git clone "https://x-access-token:${GH_PAT}@github.com/${GH_BACKUP_USER}/${GH_REPO}.git"
cd "${GH_REPO}"
rm -f dashboard-*.tar.gz recover-current.tar.gz
cp /tmp/dashboard-${TIME}.tar.gz .
echo "dashboard-${TIME}.tar.gz" > README.md
git config user.name "${GH_BACKUP_USER}"
git config user.email "${GH_EMAIL}"
git add -A
git commit -m "backup ${TIME}"
git push origin main

rm -f /tmp/dashboard-${TIME}.tar.gz
echo "==== DONE: dashboard-${TIME}.tar.gz uploaded to ${GH_BACKUP_USER}/${GH_REPO} ===="
