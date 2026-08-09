#!/usr/bin/env bash

# backup.sh 传参 a 自动还原； 传参 m 手动还原； 传参 f 强制更新面板 app 文件及 cloudflared 文件，并备份数据至成备份库。
# 如是 IPv6 only 或者大陆机器，需要 Github 加速网，可自行查找放在 GH_PROXY 处 ，如 https://mirror.ghproxy.com/ ，能不用就不用，减少因加速网导致的故障。

GH_PROXY=
GH_PAT=
GH_BACKUP_USER=
GH_EMAIL=
GH_REPO=
SYSTEM=
ARCH=
WORK_DIR=
DAYS=10
IS_DOCKER=
DASHBOARD_VERSION=

########

# version: 2024.12.18

warning() { echo -e "\033[31m\033[01m$*\033[0m"; }  # 红色
error() { echo -e "\033[31m\033[01m$*\033[0m" && exit 1; } # 红色
info() { echo -e "\033[32m\033[01m$*\033[0m"; }   # 绿色
hint() { echo -e "\033[33m\033[01m$*\033[0m"; }   # 黄色

cmd_systemctl() {
  local ENABLE_DISABLE=$1
  if [ "$ENABLE_DISABLE" = 'enable' ]; then
    if [ "$SYSTEM" = 'Alpine' ]; then
      local TRY=5
      until [ $(systemctl is-active nezha-dashboard) = 'active' ]; do
        systemctl stop nezha-dashboard; sleep 1
        systemctl start nezha-dashboard
        ((TRY--))
        [ "$TRY" = 0 ] && break
      done
      cat > /etc/local.d/nezha-dashboard.start << ABC
#!/usr/bin/env bash

systemctl start nezha-dashboard
ABC
      chmod +x /etc/local.d/nezha-dashboard.start
      rc-update add local >/dev/null 2>&1
    else
      systemctl enable --now nezha-dashboard
    fi

  elif [ "$ENABLE_DISABLE" = 'disable' ]; then
    if [ "$SYSTEM" = 'Alpine' ]; then
      systemctl stop nezha-dashboard
      rm -f /etc/local.d/nezha-dashboard.start
    else
      systemctl disable --now nezha-dashboard
    fi
  fi
}

# 运行备份脚本时，自锁一定时间以防 Github 缓存的原因导致数据马上被还原
touch $(awk -F '=' '/NO_ACTION_FLAG/{print $2; exit}' $WORK_DIR/restore.sh)1

# 手自动标志
[ "$1" = 'a' ] && WAY=Scheduled || WAY=Manualed
[ "$1" = 'f' ] && WAY=Manualed && FORCE_UPDATE=true

# 检查更新面板主程序 app 及 cloudflared
if [ -z "$DASHBOARD_VERSION" ]; then
  cd $WORK_DIR
  DASHBOARD_NOW=$(./app -v)
  DASHBOARD_LATEST=$(wget -qO- https://api.github.com/repos/naiba/nezha/releases/latest | awk -F '"' '/tag_name/{print $4}')
  [ "v${DASHBOARD_NOW}" != "$DASHBOARD_LATEST" ] && DASHBOARD_UPDATE=true
elif [[ "$DASHBOARD_VERSION" =~ [0-1]{1}\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
  cd $WORK_DIR
  DASHBOARD_NOW=$(./app -v)
  DASHBOARD_LATEST=$(sed 's/v//; s/^/v&/' <<< "$DASHBOARD_VERSION")
  [ "v${DASHBOARD_NOW}" != "$DASHBOARD_LATEST" ] && DASHBOARD_UPDATE=true
else
  error "The DASHBOARD_VERSION variable should be in a format like v0.00.00, please check."
fi

CLOUDFLARED_NOW=$(./cloudflared -v | awk '{for (i=0; i<NF; i++) if ($i=="version") {print $(i+1)}}')
CLOUDFLARED_LATEST=$(wget -qO- https://api.github.com/repos/cloudflare/cloudflared/releases/latest | awk -F '"' '/tag_name/{print $4}')
[[ "$CLOUDFLARED_LATEST" =~ ^20[0-9]{2}\.[0-9]{1,2}\.[0-9]+$ && "$CLOUDFLARED_NOW" != "$CLOUDFLARED_LATEST" ]] && CLOUDFLARED_UPDATE=true

# 检测是否有设置备份数据
if [[ -n "$GH_REPO" && -n "$GH_BACKUP_USER" && -n "$GH_EMAIL" && -n "$GH_PAT" ]]; then
  IS_PRIVATE="$(wget -qO- --header="Authorization: token $GH_PAT" https://api.github.com/repos/$GH_BACKUP_USER/$GH_REPO | sed -n '/"private":/s/.*:[ ]*\([^,]*\),/\1/gp')"
  if [ "$?" != 0 ]; then
    warning "\n Could not connect to Github. Stop backup. \n"
  elif [ "$IS_PRIVATE" != true ]; then
    warning "\n This is not exist nor a private repository. \n"
  else
    IS_BACKUP=true
  fi
fi

# 分步骤处理
if [[ "${DASHBOARD_UPDATE}${CLOUDFLARED_UPDATE}${IS_BACKUP}${FORCE_UPDATE}" =~ true ]]; then
  # 更新面板主程序
  if [[ "${DASHBOARD_UPDATE}${FORCE_UPDATE}" =~ 'true' ]]; then
    hint "\n Renew dashboard app to $DASHBOARD_LATEST \n"
    wget -O /tmp/dashboard.zip ${GH_PROXY}https://github.com/naiba/nezha/releases/download/$DASHBOARD_LATEST/dashboard-linux-$ARCH.zip
    unzip -o /tmp/dashboard.zip -d /tmp
    chmod +x /tmp/dashboard-linux-$ARCH
    if [ -s /tmp/dashboard-linux-$ARCH ]; then
      info "\n Restart Nezha Dashboard \n"
      if [ "$IS_DOCKER" = 1 ]; then
        supervisorctl stop nezha >/dev/null 2>&1
        sleep 10
        mv -f /tmp/dashboard-linux-$ARCH $WORK_DIR/app
        supervisorctl start nezha >/dev/null 2>&1
      else
        cmd_systemctl disable >/dev/null 2>&1
        sleep 10
        mv -f /tmp/dashboard-linux-$ARCH $WORK_DIR/app
        cmd_systemctl enable >/dev/null 2>&1
      fi
    fi
    rm -rf /tmp/dist /tmp/dashboard.zip
  fi

  # 更新 cloudflared
  if [[ "${CLOUDFLARED_UPDATE}${FORCE_UPDATE}" =~ 'true' ]]; then
    hint "\n Renew Cloudflared to $CLOUDFLARED_LATEST \n"
    wget -O /tmp/cloudflared ${GH_PROXY}https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH && chmod +x /tmp/cloudflared
    if [ -s /tmp/cloudflared ]; then
      info "\n Restart Argo \n"
      if [ "$IS_DOCKER" = 1 ]; then
        supervisorctl stop argo >/dev/null 2>&1
        mv -f /tmp/cloudflared $WORK_DIR/
        supervisorctl start argo >/dev/null 2>&1
      else
        cmd_systemctl disable >/dev/null 2>&1
        mv -f /tmp/cloudflared $WORK_DIR/
        cmd_systemctl enable >/dev/null 2>&1
      fi
    fi
  fi

  # 在线快照数据库，压缩备份，通过 GitHub API 上传（不 clone 仓库，本地仅占 1 份备份的空间）
  if [ "$IS_BACKUP" = 'true' ]; then
    # DAYS 安全阀：缺失或非法时回退为 10，且最小为 2，防止保留数被算成 0 而误删全部备份
    DAYS=${DAYS:-10}
    [[ "$DAYS" =~ ^[0-9]+$ ]] || DAYS=10
    [ "$DAYS" -lt 2 ] && DAYS=2

    # 备份通过 GitHub Contents API 上传，需要 curl
    command -v curl >/dev/null 2>&1 || error "\n curl is required for GitHub API backup, please install curl. \n"

    # 在线快照 sqlite（.backup 原子安全），不停面板，避免停机窗口与中途重启的风险
    SNAP_DIR=/tmp/backup_snap
    rm -rf $SNAP_DIR && mkdir -p $SNAP_DIR/data
    cp -f data/config.yaml $SNAP_DIR/data/ 2>/dev/null
    sqlite3 data/sqlite.db ".backup '$SNAP_DIR/data/sqlite.db'" || {
      rm -rf $SNAP_DIR
      error "\n Failed to snapshot sqlite.db, stop backup. \n"
    }
    # 复制自定义主题，保持与原备份包相同的 data/ resource/ 目录结构
    [ -d resource ] && find resource/ -type d -name "*custom*" -exec cp -rf --parents {} $SNAP_DIR/ \;

    TIME=$(date "+%Y-%m-%d-%H:%M:%S")
    FILE="dashboard-$TIME.tar.gz"
    echo "↓↓↓↓↓↓↓↓↓↓ $FILE list ↓↓↓↓↓↓↓↓↓↓"
    tar czvf /tmp/$FILE -C $SNAP_DIR data resource 2>/dev/null || tar czvf /tmp/$FILE -C $SNAP_DIR data
    echo -e "↑↑↑↑↑↑↑↑↑↑ $FILE list ↑↑↑↑↑↑↑↑↑↑\n\n"
    rm -rf $SNAP_DIR

    # GitHub API
    API="https://api.github.com/repos/$GH_BACKUP_USER/$GH_REPO"
    AUTH="Authorization: token $GH_PAT"
    b64() { base64 | tr -d '\n'; }

    # 1. 上传新备份文件（文件名唯一，无需 sha）
    { printf '{"message":"%s","content":"' "$WAY at $TIME"; b64 < /tmp/$FILE; printf '"}'; } > /tmp/api_payload.json
    IS_UPLOAD=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "$AUTH" -H "Content-Type: application/json" --data-binary @/tmp/api_payload.json "$API/contents/$FILE")
    rm -f /tmp/api_payload.json

    # 2. 更新 README.md 记录当前备份文件名（restore.sh 每分钟据此还原）
    README_SHA=$(curl -s -H "$AUTH" "$API/contents/README.md" | awk -F '"' '{ for (i=1; i<=NF; i++) if ($i == "sha") { print $(i+2); break } }')
    { printf '{"message":"update README","content":"'; printf '%s' "$FILE" | b64; [ -n "$README_SHA" ] && printf '","sha":"%s"' "$README_SHA"; printf '"}'; } > /tmp/api_payload.json
    IS_README=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "$AUTH" -H "Content-Type: application/json" --data-binary @/tmp/api_payload.json "$API/contents/README.md")
    rm -f /tmp/api_payload.json

    # 3. 删除最旧的备份，仅保留最近 $DAYS 个（用 contents API 列出的 path+sha 成对删除）
    curl -s -H "$AUTH" "$API/contents/" | awk -F '"' '
      { for (i=1; i<=NF; i++) {
          if ($i == "path")            { p = $(i+2) }
          else if ($i == "sha" && p ~ /\.tar\.gz$/) { print p, $(i+2); p = "" }
        }
      }' | sort > /tmp/backup_list.txt
    TOTAL=$(wc -l < /tmp/backup_list.txt)
    if [ "$TOTAL" -gt "$DAYS" ]; then
      head -n $((TOTAL-DAYS)) /tmp/backup_list.txt | while read -r OLD SHA; do
        [ -z "$OLD" ] && continue
        curl -s -o /dev/null -X DELETE -H "$AUTH" -H "Content-Type: application/json" -d "{\"message\":\"delete $OLD\",\"sha\":\"$SHA\"}" "$API/contents/$OLD"
      done
    fi
    rm -f /tmp/backup_list.txt

    # 上传与 README 更新都返回 2xx 才算成功
    if [[ "$IS_UPLOAD" =~ ^2[0-9][0-9]$ && "$IS_README" =~ ^2[0-9][0-9]$ ]]; then
      echo "$FILE" > $WORK_DIR/dbfile
      rm -f /tmp/$FILE
      info "\n Succeed to upload the backup file $FILE to Github.\n"
    else
      rm -f /tmp/$FILE $(awk -F '=' '/NO_ACTION_FLAG/{print $2; exit}' $WORK_DIR/restore.sh)*
      hint "\n Failed to upload the backup file $FILE to Github. (upload: $IS_UPLOAD, README: $IS_README)\n"
    fi
  fi
fi

if [ "$IS_DOCKER" = 1 ]; then
  supervisorctl start nezha >/dev/null 2>&1
  [ $(supervisorctl status all | grep -c "RUNNING") = $(grep -c '\[program:.*\]' /etc/supervisor/conf.d/damon.conf) ] && info "\n All programs started! \n" || error "\n Failed to start program! \n"
else
  cmd_systemctl enable >/dev/null 2>&1
  [ "$(systemctl is-active nezha-dashboard)" = 'active' ] && info "\n Nezha dashboard started! \n" || error "\n Failed to start Nezha dashboard! \n"
fi
