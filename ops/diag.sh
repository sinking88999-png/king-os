#!/usr/bin/env bash
# KING OS 服务器体检脚本（只读，不改任何东西）
# 用法: curl -sL https://raw.githubusercontent.com/sinking88999-png/king-os/main/ops/diag.sh | sudo bash
set -u
line(){ echo; echo "===== $* ====="; }

line HOST; hostname; uptime; df -h / | tail -1; free -m | head -2

line DOCKER
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "no docker"

line LISTEN
ss -ltnp 2>/dev/null | awk 'NR==1 || /:80 |:443 |:8[0-9]{3} /'

line PROXY-TYPE
for p in caddy nginx traefik; do
  if docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -qi "$p"; then echo "docker: $p"; fi
  if systemctl is-active --quiet "$p" 2>/dev/null; then echo "systemd: $p"; fi
done

line CADDY-CONFIG
for f in /etc/caddy/Caddyfile /srv/*/deploy/Caddyfile /srv/*/Caddyfile /opt/*/Caddyfile /root/*/Caddyfile; do
  [ -f "$f" ] && { echo "--- $f"; cat "$f"; }
done
docker ps -q 2>/dev/null | while read c; do
  n=$(docker inspect -f '{{.Name}}' "$c");
  if docker inspect -f '{{.Config.Image}}' "$c" | grep -qi caddy; then
    echo "--- container $n Caddyfile"; docker exec "$c" cat /etc/caddy/Caddyfile 2>/dev/null
  fi
done

line NGINX-CONFIG
ls /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null
grep -rhE 'server_name|ssl_certificate ' /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null

line CERTS
ls -la /etc/letsencrypt/live 2>/dev/null
find / -path /proc -prune -o -type d -name 'certificates' -print 2>/dev/null | grep -i caddy | head
find / -path /proc -prune -o -type d -path '*caddy*/certificates/*' -print 2>/dev/null | head
for d in $(find / -path /proc -prune -o -type d -path '*certificates/acme*' -print 2>/dev/null); do echo "--- $d"; ls "$d"; done

line PROXY-LOGS-LAST-60
docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'caddy|nginx|proxy' | while read n; do echo "--- $n"; docker logs --tail 60 "$n" 2>&1 | grep -iE 'error|tls|certificate|acme|rate' | tail -30; done
journalctl -u caddy -n 40 --no-pager 2>/dev/null | grep -iE 'error|tls|certificate|acme' | tail -20
journalctl -u nginx -n 20 --no-pager 2>/dev/null | tail -10

line COMPOSE-FILES
find /srv /opt /root /home -maxdepth 3 -name 'docker-compose*.y*ml' -o -maxdepth 3 -name 'compose*.y*ml' 2>/dev/null

line KG-LITE
ls -la /srv/kg-lite 2>/dev/null | head -20
[ -f /etc/kg-lite.env ] && { echo "env keys:"; sed -E 's/=.*/=<hidden>/' /etc/kg-lite.env; }
curl -s -o /dev/null -w "local kg-lite http: %{http_code}\n" http://127.0.0.1:8200/ 2>/dev/null

line GCP-IDENTITY
curl -s -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email'; echo
curl -s -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/scopes'
echo "project: $(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)"
echo "zone: $(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone)"

line CRON
crontab -l 2>/dev/null; ls /etc/cron.d 2>/dev/null

line DONE
