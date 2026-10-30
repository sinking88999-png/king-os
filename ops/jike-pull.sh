#!/usr/bin/env bash
# 在 instance-sg 上跑：从旧服务器拉即刻最新数据到暂存目录，并和新服务器现有数据对比。不覆盖任何线上文件。
set -u
OLD=179.236.105.34
K=/root/.ssh/id_ed25519_migrate
SSHO="-i $K -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"
STAMP=$(date +%Y%m%d-%H%M%S)
STG=/srv/migrate/jike-$STAMP
say(){ echo "[pull] $*"; }
ssh -n $SSHO root@$OLD 'echo connected $(hostname)' 2>&1 | sed 's/^/[pull] /' || { say "连不上旧服务器"; exit 1; }
mkdir -p "$STG"
# 旧站已无流量（域名 10/29 已切走），直接拷库文件（含 wal/shm 如有）和上传目录
for f in jike.sqlite jike.sqlite-wal jike.sqlite-shm; do
  scp -q $SSHO root@$OLD:/var/lib/jike/$f "$STG/old-$f" 2>/dev/null && say "拷贝 $f"
done
mv "$STG/old-jike.sqlite" "$STG/old-jike.sqlite" 2>/dev/null
[ -f "$STG/old-jike.sqlite-wal" ] && mv "$STG/old-jike.sqlite-wal" "$STG/old-jike.sqlite-wal"
mkdir -p "$STG/old-uploads"
ssh -n $SSHO root@$OLD 'tar -C /var/lib/jike/uploads -czf - .' | tar -C "$STG/old-uploads" -xzf -
say "暂存: $(du -sh $STG | cut -f1)  上传文件数: $(find $STG/old-uploads -type f | wc -l)"
# 找新服务器上即刻正在用的库
NEWDB=$(ls -t /var/lib/jike/jike.sqlite /srv/jike/*.sqlite /srv/jike/data/*.sqlite /srv/jike/*/jike.sqlite 2>/dev/null | head -1)
NEWUP=$(ls -d /var/lib/jike/uploads /srv/jike/uploads /srv/jike/data/uploads 2>/dev/null | head -1)
say "新库: ${NEWDB:-未找到}  新上传: ${NEWUP:-未找到}"
say "即刻进程: $(ps -eo pid,cmd | grep -E 'next-server|jike' | grep -v grep | head -3 | tr -s ' ' | tr '\n' ';')"
python3 - "$STG/old-jike.sqlite" "${NEWDB:-}" <<'PY'
import sqlite3, sys
old, new = sys.argv[1], sys.argv[2]
def info(p):
    c = sqlite3.connect(p); r = {}
    for (t,) in c.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%'"):
        n = c.execute(f'select count(*) from "{t}"').fetchone()[0]
        cols = [x[1] for x in c.execute(f'pragma table_info("{t}")')]
        tc = next((x for x in ("updated_at","created_at","createdAt","updatedAt","ts","time") if x in cols), None)
        last = c.execute(f'select max("{tc}") from "{t}"').fetchone()[0] if tc else None
        r[t] = (n, last)
    return r
o = info(old); nw = info(new) if new else {}
print("[pull] 表名 | 旧服务器行数/最新时间 | 新服务器行数/最新时间")
for t in sorted(set(o) | set(nw)):
    a = o.get(t, ("-", "")); b = nw.get(t, ("-", ""))
    flag = "  <-- 新服务器有新增" if (isinstance(b[0], int) and isinstance(a[0], int) and b[1] and a[1] and str(b[1]) > str(a[1])) else ""
    print(f"[pull] {t} | {a[0]} / {a[1]} | {b[0]} / {b[1]}{flag}")
PY
echo "$STG" > /srv/migrate/LATEST
say DONE
