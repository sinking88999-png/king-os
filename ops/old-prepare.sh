#!/usr/bin/env bash
# 在旧服务器 179.236.105.34 上跑：允许新服务器 instance-sg 用密钥登录（只读迁移用），并盘点即刻 / 办理进度相关内容
set -u
PUB='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJjRcrdA8TFHTwdjBm01RwBWxkjH4Oz7pQe95a6pYkbF migrate@instance-sg'
mkdir -p /root/.ssh && chmod 700 /root/.ssh
grep -qF "$PUB" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUB" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "[old] key ok; sshd: $(systemctl is-active sshd ssh 2>/dev/null | tr '\n' ' '); PubkeyAuth: $(sshd -T 2>/dev/null | grep -i pubkeyauthentication)"
echo "[old] host=$(hostname) up=$(uptime -p) disk=$(df -h / | awk 'NR==2{print $3"/"$2}')"
echo "[old] docker: $(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
echo "[old] listen: $(ss -ltnp 2>/dev/null | awk 'NR>1{print $4}' | sed 's/.*://' | sort -un | tr '\n' ' ')"
echo "[old] proxy conf hosts:"
grep -rhoE '^[a-z0-9.-]+\.(com|ai|io)[^{]*\{|server_name [^;]+' /etc/caddy /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | sort -u | head -20
echo "[old] jike dirs:"
find / -maxdepth 4 \( -path /proc -o -path /sys -o -path /var/lib/docker \) -prune -o -type d -iname '*jike*' -print 2>/dev/null | head
echo "[old] sqlite files (newest 15):"
find / \( -path /proc -o -path /sys -o -path /var/lib/docker/overlay2 \) -prune -o -type f \( -name '*.sqlite3' -o -name '*.sqlite' -o -name '*.db' \) -size +20k -printf '%TY-%Tm-%Td %TH:%TM %10s %p\n' 2>/dev/null | sort -r | head -15
echo "[old] uploads dirs:"
find / \( -path /proc -o -path /sys -o -path /var/lib/docker \) -prune -o -type d \( -iname 'uploads' -o -iname 'upload' -o -iname 'media' \) -print 2>/dev/null | grep -v node_modules | head
echo "[old] progress related:"
grep -rlis 'progress' /etc/caddy /etc/nginx 2>/dev/null | head -3
ls -d /opt/* /srv/* /var/www/* 2>/dev/null | tr '\n' ' '; echo
echo "[old] DONE"
