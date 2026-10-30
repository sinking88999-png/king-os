#!/usr/bin/env bash
# up2: 所有服务开机自启。caddy/docker 设为 enabled；容器设 restart=unless-stopped；即刻 Next.js 改由 systemd 托管。
set -u
say(){ echo "[up2] $*"; }
for s in caddy docker cron; do systemctl enable "$s" >/dev/null 2>&1; say "$s: $(systemctl is-enabled $s 2>/dev/null)/$(systemctl is-active $s 2>/dev/null)"; done
for c in $(docker ps --format '{{.Names}}'); do
  p=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c")
  if [ "$p" = "no" ] || [ -z "$p" ]; then docker update --restart unless-stopped "$c" >/dev/null && p="unless-stopped(已改)"; fi
  say "容器 $c: $p"
done

# 即刻：找出 3000 端口进程的启动方式
PID=$(ss -ltnp | grep '127.0.0.1:3000 ' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
if systemctl list-units --type=service --all | grep -qiE 'jike'; then
  say "即刻已有 systemd 服务: $(systemctl list-units --type=service --all | grep -iE jike | awk '{print $1, $3, $4}')"
  say "开机自启: $(systemctl is-enabled $(systemctl list-units --type=service --all | grep -iE jike | awk '{print $1}' | head -1))"
elif [ -n "$PID" ]; then
  CWD=$(readlink /proc/$PID/cwd); PP=$(ps -o ppid= -p $PID | tr -d ' ')
  say "即刻进程 $PID 目录 $CWD 父进程: $(ps -o cmd= -p $PP | cut -c1-120)"
  say "父进程所属 systemd 单元: $(cat /proc/$PID/cgroup | grep -oE '[a-z0-9@._-]+\.service' | head -1)"
  NODE=$(readlink /proc/$PID/exe)
  ENVKEYS=$(tr '\0' '\n' < /proc/$PID/environ | grep -E '^(NODE_ENV|PORT|HOSTNAME|DATABASE|JIKE|NEXT)' | sed 's/=.*//' | tr '\n' ' ')
  say "node: $NODE  关键环境变量名: $ENVKEYS"
  UNIT=$(cat /proc/$PID/cgroup | grep -oE '[a-z0-9@._-]+\.service' | head -1)
  if [ -n "$UNIT" ] && [ "$UNIT" != "session-*.scope" ]; then
    systemctl enable "$UNIT" >/dev/null 2>&1; say "已启用 $UNIT 开机自启: $(systemctl is-enabled $UNIT 2>/dev/null)"
  else
    # 生成 systemd 单元（环境变量原样带上），切换时即刻停 3-5 秒
    tr '\0' '\n' < /proc/$PID/environ | grep -vE '^(_|PWD|OLDPWD|SHLVL|TERM|SSH_|MAIL|LOGNAME|USER|HOME|SUDO_)' > /etc/jike.env
    chmod 600 /etc/jike.env
    START=$(grep -qs '"start"' "$CWD/package.json" && echo "$(dirname $NODE)/npm run start" || echo "$NODE $CWD/node_modules/.bin/next start -p 3000 -H 127.0.0.1")
    cat > /etc/systemd/system/jike.service <<EOF
[Unit]
Description=即刻 sgjike.com (Next.js)
After=network-online.target
[Service]
WorkingDirectory=$CWD
EnvironmentFile=/etc/jike.env
ExecStart=$START
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable jike.service >/dev/null 2>&1
    kill $PID; sleep 2; kill -9 $PP 2>/dev/null; systemctl start jike.service; sleep 8
    say "jike.service: $(systemctl is-enabled jike)/$(systemctl is-active jike)"
  fi
fi
sleep 2
for h in sgjike.com www.sghitp.com kg.sghitp.com growth.sghitp.com; do
  say "$h -> $(curl -s -o /dev/null -m 15 -w '%{http_code}' --resolve $h:443:127.0.0.1 https://$h/)"
done
say DONE
