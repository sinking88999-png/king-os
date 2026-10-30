#!/bin/bash
# Read-only: what is instance-hk doing? (run from Cloud Shell)
gcloud compute ssh instance-hk --zone asia-east2-a --tunnel-through-iap --quiet --command '
echo "== uptime"; uptime
echo "== docker"; sudo docker ps --format "{{.Names}} | {{.Image}} | {{.Status}}" 2>/dev/null | head -20
echo "== listening"; sudo ss -tlnp | awk "NR>1{print \$4, \$6}" | head -25
echo "== services"; systemctl list-units --type=service --state=running --no-legend | awk "{print \$1}" | grep -vE "^(systemd|dbus|cron|ssh|google|rsyslog|chrony|polkit|unattended|serial|getty|user@|networkd|snapd|containerd|multipathd|udisks|ModemManager|accounts|irqbalance|haveged|packagekit|qemu)"
echo "== caddy/nginx hosts"; sudo grep -hE "^[a-z0-9].*\{|server_name" /etc/caddy/Caddyfile /etc/nginx/sites-enabled/* 2>/dev/null | head -20
echo "== web hits 3d"; sudo journalctl -u caddy --since "-3 days" 2>/dev/null | grep -c "handled request"; sudo find /var/log/nginx -name "access.log*" -mtime -3 2>/dev/null | xargs -r sudo cat 2>/dev/null | wc -l
echo "== disk"; df -h / | tail -1; sudo du -sh /opt/* /srv/* /root 2>/dev/null | sort -h | tail -8
echo "== logins"; last -n 6 2>/dev/null | head -6
' 2>&1 | tail -80
echo "== net bytes 3d"
gcloud compute instances describe instance-hk --zone asia-east2-a --format="value(id,creationTimestamp,lastStartTimestamp)"
