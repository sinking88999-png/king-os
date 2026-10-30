#!/usr/bin/env bash
# up1: 备份每晚 03:40 同步到 Cloud Storage + 立即同步一次 + 从云端做一次恢复演练（只在临时目录，不碰线上）
set -u
say(){ echo "[up1] $*"; }
BUCKET=$(grep -E '^KG_BACKUP_BUCKET=' /etc/kg-lite.env | cut -d= -f2-)
[ -n "$BUCKET" ] || { say "没有 KG_BACKUP_BUCKET"; exit 1; }

cat > /usr/local/bin/kg-backup-sync.sh <<EOF
#!/usr/bin/env bash
# 每晚把 /srv/backups 同步到 gs://$BUCKET（用户 2026-10-30 批准）
/usr/bin/gsutil -m -q rsync -r /srv/backups gs://$BUCKET/instance-sg >> /var/log/kg-backup-sync.log 2>&1 && echo "\$(date -Is) ok" >> /var/log/kg-backup-sync.log || echo "\$(date -Is) FAIL" >> /var/log/kg-backup-sync.log
EOF
chmod 755 /usr/local/bin/kg-backup-sync.sh
echo '40 3 * * * root /usr/local/bin/kg-backup-sync.sh' > /etc/cron.d/kg-backup-sync
chmod 644 /etc/cron.d/kg-backup-sync
/usr/local/bin/kg-backup-sync.sh
say "同步: $(tail -1 /var/log/kg-backup-sync.log)"
say "云端文件数: $(gsutil ls gs://$BUCKET/instance-sg/ 2>/dev/null | wc -l)"
say "本机备份目录内容: $(ls /srv/backups | sed -E 's/-[0-9]{8}-[0-9]{6}.*//' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"

# 恢复演练：从云端拉最新一份每类备份到临时目录，解压并做完整性检查
R=/tmp/restore-drill-$(date +%Y%m%d-%H%M%S); mkdir -p "$R"
for kind in $(gsutil ls gs://$BUCKET/instance-sg/ | sed -E 's#.*/##; s/-[0-9]{8}-[0-9]{6}.*//' | sort -u); do
  f=$(gsutil ls "gs://$BUCKET/instance-sg/$kind-*" | sort | tail -1)
  gsutil -q cp "$f" "$R/" || { say "下载失败 $f"; continue; }
  b="$R/$(basename "$f")"
  case "$b" in
    *.sqlite3.gz|*.sqlite.gz|*.db.gz)
      gunzip -f "$b"; db="${b%.gz}"
      r=$(python3 -c "import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);print(c.execute('pragma integrity_check').fetchone()[0], sum(c.execute(f'select count(*) from \"{t}\"').fetchone()[0] for (t,) in c.execute(\"select name from sqlite_master where type='table'\").fetchall()))" "$db" 2>&1)
      say "恢复 $kind: 完整性/总行数 = $r";;
    *.tgz|*.tar.gz)
      n=$(tar -tzf "$b" 2>/dev/null | wc -l); say "恢复 $kind: 压缩包可读，$n 个条目";;
    *) say "恢复 $kind: $(basename "$b") $(stat -c %s "$b") 字节";;
  esac
done
rm -rf "$R"
say DONE
