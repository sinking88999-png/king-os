#!/usr/bin/env bash
# 在 instance-sg 上生成迁移用的 SSH 密钥（只生成一次），只打印公钥
set -u
K=/root/.ssh/id_ed25519_migrate
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -f "$K" ] || ssh-keygen -t ed25519 -N '' -C migrate@instance-sg -f "$K" -q
echo "[pub] $(cat $K.pub)"
