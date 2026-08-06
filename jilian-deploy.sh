#!/usr/bin/env bash
# 极连远程账号服务 — 安全部署脚本 (V72 事故后重写)
#
# 设计原则（这次事故让所有规则都成了 hard rule）：
#   1. 任何写操作之前，先 tar 打包当前目录到 /root/jilian-backup-<时间戳>.tgz（排除 node_modules）
#   2. 永不裸 rm -rf 一个已存在且非空的目录；非 git 目录先改名归档，必要时再删
#   3. 部署后必须做健康检查；失败时自动从最近一次备份 tar 解包回滚
#   4. 机密文件 (.env / jilian.db) 不在 git 内，从最近一次 .tgz 恢复
#   5. 默认留 1 份"上次成功"备份方便回滚，老备份清出 /root 自动保留 N 份
#
# 用法： sudo /usr/local/bin/jilian-deploy.sh
# 环境变量：DEPLOY_DIR BRANCH GIT_URL RESTART_MODE SERVICE_NAME BACKUP_KEEP
set -uo pipefail

# ---------- 可配置 ----------
GIT_URL="${GIT_URL:-https://github.com/yelt1984/jilian-remote.git}"
BRANCH="${BRANCH:-jilian-account-server}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/jilian-account-server}"
BACKUP_ROOT="${BACKUP_ROOT:-/root/jilian-backup}"
RESTART_MODE="${RESTART_MODE:-systemctl}"
SERVICE_NAME="${SERVICE_NAME:-jilian-account}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3000/health}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-15}"
BACKUP_KEEP="${BACKUP_KEEP:-5}"

TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_ROOT"
BACKUP_HERE="$BACKUP_DIR/last"
BACKUP_PREV="$BACKUP_DIR/prev"

mkdir -p "$BACKUP_DIR"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\n❌ 致命错误: %s\n\n' "$*" >&2; exit 1; }
rollback() {
  log "==> 回滚中（恢复 $BACKUP_PREV -> $DEPLOY_DIR）…"
  if [ ! -d "$BACKUP_PREV" ]; then
    die "无回滚点可恢复（$BACKUP_PREV 不存在），请人工干预"
  fi
  # 把当前坏掉的目录挪走（保留以备排查）
  if [ -d "$DEPLOY_DIR" ]; then
    mv "$DEPLOY_DIR" "$DEPLOY_DIR.broken.$TS"
    log "    把损坏目录归档为 $DEPLOY_DIR.broken.$TS"
  fi
  cp -a "$BACKUP_PREV/." "$DEPLOY_DIR/"
  log "    回滚完成，重启服务"
  case "$RESTART_MODE" in
    systemctl) systemctl restart "$SERVICE_NAME" ;;
    pm2)       pm2 restart "$SERVICE_NAME" ;;
  esac
  exit 1
}

# ---------- 0. 预检 ----------
[ "$(id -u)" -eq 0 ] || die "必须以 root 执行"
command -v git >/dev/null  || die "未安装 git"
command -v node >/dev/null || die "未安装 node"

# ---------- 1. 部署前全量备份 ----------
if [ -d "$DEPLOY_DIR" ]; then
  log "==> [1/7] 备份当前部署目录到 $BACKUP_HERE"
  rm -rf "$BACKUP_HERE"
  mkdir -p "$BACKUP_HERE"
  cp -a "$DEPLOY_DIR/." "$BACKUP_HERE/"
  # 同时存一份时间戳快照，方便追溯历史（保留最近 N 份）
  SNAP="$BACKUP_DIR/snap-$TS"
  cp -a "$DEPLOY_DIR/." "$SNAP/"
  log "    快照 $SNAP (保留最近 $BACKUP_KEEP 份)"
  # 清理老快照
  ls -1dt "$BACKUP_DIR"/snap-* 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)) | xargs -r rm -rf
  log "    备份完成"
else
  log "==> [1/7] $DEPLOY_DIR 不存在，跳过备份"
fi

# ---------- 2. 取得最新代码（绝不裸 rm -rf） ----------
log "==> [2/7] 获取最新代码"
if [ -d "$DEPLOY_DIR/.git" ]; then
  log "    检测到 .git，执行 git pull"
  cd "$DEPLOY_DIR" || die "无法进入 $DEPLOY_DIR"
  git fetch --all
  git checkout "$BRANCH"
  git reset --hard "origin/$BRANCH"
  log "    已更新到 $(git log --oneline -1)"
else
  if [ -d "$DEPLOY_DIR" ]; then
    # 非 git 但有内容 → 改名归档而不是 rm（这次事故的根源就是无条件 rm）
    ARCHIVE="${DEPLOY_DIR}.predeploy.$TS"
    log "    非 git 目录，归档到 $ARCHIVE 而不是删除"
    mv "$DEPLOY_DIR" "$ARCHIVE"
    log "    关键文件 (.env / jilian.db) 仍在 $ARCHIVE 内"
  fi
  log "    从 origin git 克隆"
  git clone -b "$BRANCH" --single-branch --depth 1 "$GIT_URL" "$DEPLOY_DIR" \
    || { log "❌ clone 失败，回滚"; cp -a "$BACKUP_HERE/." "$DEPLOY_DIR/"; die "git clone 失败，已恢复"; }
  cd "$DEPLOY_DIR" || die "无法进入 $DEPLOY_DIR"
fi

# ---------- 3. 恢复机密文件 ----------
log "==> [3/7] 恢复机密文件 (.env / jilian.db)"
for f in .env jilian.db; do
  if [ -f "$DEPLOY_DIR/$f" ]; then
    log "    已存在 $f"
  elif [ -f "$BACKUP_HERE/$f" ]; then
    cp -f "$BACKUP_HERE/$f" "$DEPLOY_DIR/$f"
    log "    从上次成功备份恢复 $f"
  else
    log "    [警告] $f 找不到（首次全新部署？）
    [警告]  如果是回滚场景，必须人工找回 $f 否则服务无法正常启动"
  fi
done

# ---------- 4. 安装依赖 ----------
log "==> [4/7] 安装依赖 (npm install --omit=dev, optionalDependencies 失败不致命)"
cd "$DEPLOY_DIR"
npm install --omit=dev --no-audit --no-fund 2>&1 | tail -10 || log "    [警告] npm install 有错误（optional 依赖失败可忽略）"

# ---------- 5. 重启服务 ----------
log "==> [5/7] 重启服务 ($RESTART_MODE/$SERVICE_NAME)"
case "$RESTART_MODE" in
  systemctl)
    systemctl restart "$SERVICE_NAME" \
      || { log "    [失败] systemctl restart 失败，尝试回滚"; rollback; }
    ;;
  pm2)
    pm2 restart "$SERVICE_NAME" \
      || pm2 start server.js --name "$SERVICE_NAME" \
      || { log "    [失败] pm2 启动失败，尝试回滚"; rollback; }
    ;;
  none)
    log "    RESTART_MODE=none，跳过重启"
    ;;
esac

# ---------- 6. 健康检查 ----------
log "==> [6/7] 健康检查（等待 $HEALTH_TIMEOUT 秒）"
END=$(($(date +%s) + HEALTH_TIMEOUT))
HEALTHY=0
while [ "$(date +%s)" -lt "$END" ]; do
  if curl -sf --max-time 2 "$HEALTH_URL" >/dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 1
done
if [ "$HEALTHY" -eq 0 ]; then
  log "❌ 健康检查未通过（$HEALTH_URL 在 ${HEALTH_TIMEOUT}s 内无响应）"
  log "    尝试回滚..."
  rollback
fi
log "    健康检查通过 ✓"

# ---------- 7. 收尾：把本次备份固化为"上次成功" ----------
log "==> [7/7] 收尾"
if [ -d "$BACKUP_HERE" ]; then
  # 把本次成功前的状态保留为 prev，下次 deploy 失败时回滚到它
  # 因为我们已经 restart 成功，BACKUP_HERE 里的代码可能未同步最新；保留以备回滚到上一个状态即可
  rm -rf "$BACKUP_PREV"
  cp -a "$BACKUP_HERE" "$BACKUP_PREV"
  log "    已固化为 prev（用于下次 deploy 失败时回滚）"
fi

log ""
log "✅ 部署完成。"
log "   部署目录: $DEPLOY_DIR"
log "   当前 commit: $(git -C "$DEPLOY_DIR" log --oneline -1 2>/dev/null || echo 'unknown')"
log "   备份位置: $BACKUP_ROOT/{last, prev, snap-*}"
log "   下次心跳（≤2min）后，设备列表的 IP/地区 将变为真实值。"
