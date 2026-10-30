#!/usr/bin/env bash
# fix6: 每天 03:40 把 /srv/backups 同步到 Cloud Storage，并立刻同步一次。幂等。
set -u
say(){ echo "[fix6] $*"; }
BUCKET=$(grep -E '^KG_BACKUP_BUCKET=' /etc/kg-lite.env | cut -d= -f2-)
[ -n "$BUCKET" ] || { say "没有 KG_BACKUP_BUCKET"; exit 1; }
cat > /usr/local/bin/kg-backup-sync.sh <<EOF
#!/usr/bin/env bash
/usr/bin/gsutil -m -q rsync -r /srv/backups gs://$BUCKET/instance-sg >> /var/log/kg-backup-sync.log 2>&1
echo "\$(date -Is) synced" >> /var/log/kg-backup-sync.log
EOF
chmod +x /usr/local/bin/kg-backup-sync.sh
echo '40 3 * * * root /usr/local/bin/kg-backup-sync.sh' > /etc/cron.d/kg-backup-sync
chmod 644 /etc/cron.d/kg-backup-sync
/usr/local/bin/kg-backup-sync.sh
say "定时: $(cat /etc/cron.d/kg-backup-sync)"
say "云端文件数: $(gsutil ls "gs://$BUCKET/instance-sg/" 2>/dev/null | wc -l)"
say "最近: $(gsutil ls "gs://$BUCKET/instance-sg/" 2>/dev/null | tail -2 | tr '\n' ' ')"
say "日志: $(tail -1 /var/log/kg-backup-sync.log)"
say DONE
