#!/usr/bin/env bash
# fix2: jike 预览指向 127.0.0.1:3000；停用 kg-lite 自带的 docker caddy；正确重载主机 Caddy。幂等。
set -u
CF=/etc/caddy/Caddyfile
COMPOSE_DIR=/srv/kg-lite/deploy
STAMP=$(date +%Y%m%d-%H%M%S)
say(){ echo "[fix2] $*"; }
cp -a "$CF" "$CF.bak-$STAMP"

# 1) jike 实际在 3000
sed -i 's#127\.0\.0\.1:3100#127.0.0.1:3000#g' "$CF"

# 2) 停用 compose 里的 caddy 服务（主机 Caddy 才是网关）
OV="$COMPOSE_DIR/docker-compose.override.yml"
if [ -f "$OV" ] && ! grep -q 'caddy:' "$OV"; then
  cat >> "$OV" <<'YML'
  caddy:
    profiles: ["disabled"]
YML
  say "override 里已停用 caddy 服务"
fi
(cd "$COMPOSE_DIR" && docker compose rm -sf caddy >/dev/null 2>&1; docker compose up -d 2>&1 | tail -2)

# 3) 校验 + 重载（这台机的 caddy.service 不支持 reload，用 caddy reload / restart）
if caddy validate --config "$CF" --adapter caddyfile >/tmp/caddy-validate.log 2>&1; then
  if caddy reload --config "$CF" --adapter caddyfile >/tmp/caddy-reload.log 2>&1; then
    say "Caddy 已热重载"
  else
    systemctl restart caddy && say "Caddy 已重启"
  fi
else
  say "校验失败，回滚"; tail -5 /tmp/caddy-validate.log; cp -a "$CF.bak-$STAMP" "$CF"; exit 1
fi

# 4) 等证书签发，再测
for i in 1 2 3 4 5 6; do
  sleep 10
  ok=1
  for h in kg hitp jike; do
    c=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "https://$h.136-85-62-199.sslip.io/" 2>/dev/null || echo ERR)
    say "第${i}次 https://$h.136-85-62-199.sslip.io -> $c"
    case "$c" in 2*|3*) ;; *) ok=0;; esac
  done
  [ $ok = 1 ] && break
done
for h in www.sghitp.com sgjike.com growth.sghitp.com; do
  c=$(curl -s -o /dev/null -m 15 -w '%{http_code}' --resolve "$h:443:127.0.0.1" "https://$h/" 2>/dev/null || echo ERR)
  say "本机验证 $h -> $c"
done
journalctl -u caddy --since "3 min ago" --no-pager 2>/dev/null | grep -iE '"level":"error"' | cut -c1-200 | tail -5
say DONE
