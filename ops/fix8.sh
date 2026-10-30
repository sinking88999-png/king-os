#!/usr/bin/env bash
# fix8: 公网屏蔽 www.sghitp.com 根目录下的 kg-*.json 内部状态文件；删除新服务器上的迁移密钥。幂等。
set -u
CF=/etc/caddy/Caddyfile
STAMP=$(date +%Y%m%d-%H%M%S)
say(){ echo "[fix8] $*"; }
cp -a "$CF" "$CF.bak-$STAMP"
if ! grep -q 'KG_HIDE_STATUS_JSON' "$CF"; then
  python3 - "$CF" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
marker = "handle {\n\t\troot * /opt/hitp-growth-os/public-site"
block = "# KG_HIDE_STATUS_JSON\n\t@kg_status_json path_regexp kgjson ^/kg-.*\\.json$\n\thandle @kg_status_json {\n\t\trespond 404\n\t}\n\n\t"
i = s.find("root * /opt/hitp-growth-os/public-site")
j = s.rfind("handle {", 0, i)
assert j != -1, "anchor not found"
s = s[:j] + block + s[j:]
open(p, "w").write(s); print("[fix8] inserted")
PY
fi
if caddy validate --config "$CF" --adapter caddyfile >/tmp/v.log 2>&1; then
  caddy reload --config "$CF" --adapter caddyfile >/dev/null 2>&1 && say "Caddy 已热重载"
else
  say "校验失败，回滚"; tail -3 /tmp/v.log; cp -a "$CF.bak-$STAMP" "$CF"; exit 1
fi
sleep 2
for f in kg-status-7f3c9a.json kg-old-status-7f3c9a.json index.html; do
  say "$f -> $(curl -s -o /dev/null -m 10 -w '%{http_code}' --resolve www.sghitp.com:443:127.0.0.1 https://www.sghitp.com/$f)"
done
say "进度接口 -> $(curl -s -m 10 --resolve www.sghitp.com:443:127.0.0.1 'https://www.sghitp.com/api/progress?code=TEST123')"
rm -f /root/.ssh/id_ed25519_migrate /root/.ssh/id_ed25519_migrate.pub && say "新服务器迁移密钥已删除"
say DONE
