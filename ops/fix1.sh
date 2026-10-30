#!/usr/bin/env bash
# fix1: 把 hitp / jike 预览站加回主机 Caddy，kg-lite 固定在 127.0.0.1:8200。幂等，可重复跑。
# 用法: curl -sL https://raw.githubusercontent.com/sinking88999-png/king-os/main/ops/fix1.sh | sudo bash
set -u
CF=/etc/caddy/Caddyfile
KGCF=/srv/kg-lite/deploy/Caddyfile
COMPOSE_DIR=/srv/kg-lite/deploy
STAMP=$(date +%Y%m%d-%H%M%S)
say(){ echo "[fix1] $*"; }

[ -f "$CF" ] || { say "没有 $CF，停止"; exit 1; }
cp -a "$CF" "$CF.bak-$STAMP"; say "已备份 $CF.bak-$STAMP"

# 1) kg-lite 发布到 127.0.0.1:8200（用 override 文件，不改原 compose）
if [ -d "$COMPOSE_DIR" ]; then
  OV="$COMPOSE_DIR/docker-compose.override.yml"
  if [ ! -f "$OV" ]; then
    cat > "$OV" <<'YML'
services:
  kg-lite:
    ports:
      - "127.0.0.1:8200:8200"
YML
    say "已写 $OV"
  fi
  (cd "$COMPOSE_DIR" && docker compose up -d 2>&1 | tail -3)
  sleep 3
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8200/ || true)
  say "kg-lite 本机 8200 -> HTTP $code"
else
  say "没有 $COMPOSE_DIR，跳过端口发布"
fi

# 2) 主机 Caddy：kg 指向 127.0.0.1:8200（不再用容器 IP）
sed -i 's#172\.18\.0\.[0-9]\+:8200#127.0.0.1:8200#g' "$CF"

# 3) 把 hitp / jike 预览块从 kg-lite 的 Caddyfile 搬过来（若主机 Caddy 里还没有）
if [ -f "$KGCF" ]; then
  if ! grep -q '^hitp\.136-85-62-199\.sslip\.io' "$CF"; then
    awk '/^hitp\.136-85-62-199\.sslip\.io/{p=1} p' "$KGCF" \
      | sed -e 's#kg-lite:8200#127.0.0.1:8200#g' -e 's#host\.docker\.internal:3100#127.0.0.1:3100#g' \
      > /tmp/kg-preview-blocks.caddy
    { echo; echo "# ---- preview sites (moved from kg-lite Caddyfile, $STAMP) ----"; cat /tmp/kg-preview-blocks.caddy; } >> "$CF"
    say "已追加 hitp/jike 预览块"
  else
    say "主机 Caddy 已有 hitp 预览块，不重复追加"
  fi
else
  say "找不到 $KGCF，无法搬预览块"
fi

# 4) 校验并重载
if caddy validate --config "$CF" --adapter caddyfile >/tmp/caddy-validate.log 2>&1; then
  systemctl reload caddy && say "Caddy 已重载"
else
  say "Caddy 配置校验失败，回滚"; tail -5 /tmp/caddy-validate.log
  cp -a "$CF.bak-$STAMP" "$CF"; systemctl reload caddy
fi

# 5) 结果
sleep 6
for h in kg hitp jike; do
  c=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "https://$h.136-85-62-199.sslip.io/" 2>/dev/null || echo ERR)
  say "https://$h.136-85-62-199.sslip.io -> $c"
done
say "jike 3100 本机: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3100/ || echo none)"
say "kg-lite 代码里 AI 接法: $(grep -rlE 'aiplatform|vertex|metadata\.google\.internal' /srv/kg-lite/app 2>/dev/null | head -3 | tr '\n' ' ')"
say "kg-lite env 变量名: $(sed -E 's/=.*//' /etc/kg-lite.env 2>/dev/null | tr '\n' ' ')"
say "SA: $(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email)"
say "scopes: $(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/scopes | tr '\n' ' ')"
say DONE
