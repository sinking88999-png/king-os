#!/usr/bin/env bash
# fix5: kg-lite 每日备份同时上传到 Google Cloud Storage（用服务器自带身份）。幂等。
set -u
ENVF=/etc/kg-lite.env
say(){ echo "[fix5] $*"; }
PROJECT=$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)
BUCKET="kg-lite-backup-${PROJECT##*-}"
command -v gsutil >/dev/null || { say "服务器没有 gsutil"; exit 1; }
if ! gsutil ls -b "gs://$BUCKET" >/dev/null 2>&1; then
  gsutil mb -p "$PROJECT" -l asia-southeast1 -b on "gs://$BUCKET" 2>&1 | tail -1 && say "已建桶 gs://$BUCKET"
else
  say "桶已存在 gs://$BUCKET"
fi
# 90 天自动清理
cat > /tmp/lc.json <<'J'
{"rule":[{"action":{"type":"Delete"},"condition":{"age":90}}]}
J
gsutil lifecycle set /tmp/lc.json "gs://$BUCKET" >/dev/null 2>&1 && say "保留 90 天"
grep -q '^KG_BACKUP_BUCKET=' "$ENVF" && sed -i "s/^KG_BACKUP_BUCKET=.*/KG_BACKUP_BUCKET=$BUCKET/" "$ENVF" || echo "KG_BACKUP_BUCKET=$BUCKET" >> "$ENVF"
# 找到备份脚本并跑一次
BK=$( (crontab -l 2>/dev/null; cat /etc/cron.d/* 2>/dev/null) | grep -iE 'backup' | grep -oE '/[^ ]*backup[^ ]*\.sh' | head -1)
say "备份脚本: ${BK:-未找到}"
if [ -n "$BK" ] && [ -f "$BK" ]; then
  set -a; . "$ENVF"; set +a
  bash "$BK" 2>&1 | tail -3
fi
say "桶内文件: $(gsutil ls "gs://$BUCKET/**" 2>/dev/null | tail -3 | tr '\n' ' ')"
say "本机备份目录: $(ls -t /srv/backups 2>/dev/null | head -3 | tr '\n' ' ')"
say DONE
