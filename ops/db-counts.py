#!/usr/bin/env python3
# 只读：打印旧版 King Growth 三个库每张表的行数和最新时间，用于新旧服务器对比
import sqlite3, os, sys
DBS = ["/opt/king-growth/data/king-growth.sqlite3", "/opt/king-os/data/kingos.db", "/opt/king-growth-saas/data/control.sqlite3"]
TS = ("updated_at", "created_at", "createdAt", "updatedAt", "ts", "received_at", "occurred_at")
for p in DBS:
    if not os.path.exists(p):
        print(f"[cnt] {os.path.basename(p)} MISSING"); continue
    c = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
    rows = []
    for (t,) in c.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name"):
        try:
            n = c.execute(f'select count(*) from "{t}"').fetchone()[0]
            cols = [x[1] for x in c.execute(f'pragma table_info("{t}")')]
            tc = next((x for x in TS if x in cols), None)
            last = c.execute(f'select max("{tc}") from "{t}"').fetchone()[0] if tc and n else ""
        except Exception:
            n, last = -1, ""
        if n:
            rows.append((t, n, str(last)[:19]))
    tot = sum(r[1] for r in rows if r[1] > 0)
    newest = max((r[2] for r in rows if r[2]), default="")
    print(f"[cnt] {os.path.basename(p)} tables={len(rows)} rows={tot} newest={newest}")
    for t, n, last in sorted(rows, key=lambda r: r[2], reverse=True)[:12]:
        print(f"[cnt]   {t}={n} @{last}")
