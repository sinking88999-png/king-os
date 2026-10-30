#!/usr/bin/env bash
# fix7: 主机 Caddy 增加 kg.sghitp.com -> kg-lite。幂等。
set -u
CF=/etc/caddy/Caddyfile
STAMP=$(date +%Y%m%d-%H%M%S)
say(){ echo "[fix7] $*"; }
cp -a "$CF" "$CF.bak-$STAMP"
if ! grep -q '^kg\.sghitp\.com' "$CF"; then
  cat >> "$CF" <<'C'

# ---- kg-lite 正式域名 ----
kg.sghitp.com {
  encode gzip
  reverse_proxy 127.0.0.1:8200
}
C
  say "已追加 kg.sghitp.com"
else
  say "已有 kg.sghitp.com 块"
fi
if caddy validate --config "$CF" --adapter caddyfile >/tmp/v.log 2>&1; then
  caddy reload --config "$CF" --adapter caddyfile >/tmp/r.log 2>&1 && say "Caddy 已热重载" || { systemctl restart caddy && say "Caddy 已重启"; }
else
  say "校验失败，回滚"; tail -3 /tmp/v.log; cp -a "$CF.bak-$STAMP" "$CF"; exit 1
fi
for i in 1 2 3 4 5 6; do
  sleep 10
  c=$(curl -s -o /dev/null -m 15 -w '%{http_code}' https://kg.sghitp.com/healthz 2>/dev/null || echo ERR)
  say "第${i}次 https://kg.sghitp.com/healthz -> $c"
  [ "$c" = 200 ] && break
done
journalctl -u caddy --since "2 min ago" --no-pager 2>/dev/null | grep -i '"level":"error"' | cut -c1-180 | tail -3
say DONE
