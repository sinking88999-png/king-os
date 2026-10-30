#!/usr/bin/env bash
# 在 instance-sg 上跑：对比旧服务器与新服务器上旧版 King Growth / King OS 数据库，看 10/28 迁移后旧服务器是否还有新写入。只读，不覆盖。
set -u
OLD=179.236.105.34
K=/root/.ssh/id_ed25519_migrate
SSHO="-i $K -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"
STG=/srv/migrate/kg-$(date +%Y%m%d-%H%M%S)
say(){ echo "[kg] $*"; }
mkdir -p "$STG"
for p in /opt/king-growth/data/king-growth.sqlite3 /opt/king-os/data/kingos.db /opt/king-growth-saas/data/control.sqlite3; do
  b=$(basename $p)
  say "旧: $(ssh -n $SSHO root@$OLD "stat -c '%y %s' $p" 2>/dev/null)  $p"
  say "新: $(stat -c '%y %s' $p 2>/dev/null || echo 无)"
  scp -q $SSHO root@$OLD:$p "$STG/old-$b" && for x in -wal -shm; do scp -q $SSHO root@$OLD:$p$x "$STG/old-$b$x" 2>/dev/null; done
done
python3 - "$STG" <<'PY'
import sqlite3, sys, os
stg = sys.argv[1]
pairs = {"king-growth.sqlite3":"/opt/king-growth/data/king-growth.sqlite3","kingos.db":"/opt/king-os/data/kingos.db","control.sqlite3":"/opt/king-growth-saas/data/control.sqlite3"}
def counts(p):
    c = sqlite3.connect(f"file:{p}?mode=ro", uri=True); r = {}
    for (t,) in c.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%'"):
        try: r[t] = c.execute(f'select count(*) from "{t}"').fetchone()[0]
        except Exception as e: r[t] = "err"
    return r
for b, newp in pairs.items():
    oldp = os.path.join(stg, "old-" + b)
    if not os.path.exists(oldp): print(f"[kg] {b}: 旧库未拷到"); continue
    o = counts(oldp); n = counts(newp) if os.path.exists(newp) else {}
    diff = [(t, o.get(t), n.get(t)) for t in sorted(set(o)|set(n)) if o.get(t) != n.get(t)]
    print(f"[kg] {b}: 表 {len(o)} 个，有差异 {len(diff)} 个；旧总行数 {sum(v for v in o.values() if isinstance(v,int))}，新总行数 {sum(v for v in n.values() if isinstance(v,int))}")
    for t, a, z in diff[:25]: print(f"[kg]    {t}: 旧 {a} / 新 {z}")
PY
echo "$STG" > /srv/migrate/LATEST_KG
say "办理进度接口(新服务器本机): $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8130/public/progress/hitp?code=TEST')"
say "办理进度接口(公网): $(curl -s -o /dev/null -w '%{http_code}' 'https://www.sghitp.com/api/progress?code=TEST')"
say "8130 进程: $(ps -o pid,cmd -p $(ss -ltnp | grep ':8130 ' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2) 2>/dev/null | tail -1 | cut -c1-120)"
say DONE
