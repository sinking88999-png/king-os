#!/usr/bin/env bash
# 在 Cloud Shell 里跑：创建一把只限 Gemini API 的密钥，直接写进服务器 /etc/kg-lite.env（不在屏幕上显示），然后在服务器上跑 fix4。
set -u
P=gen-lang-client-0724339507
ZONE=asia-southeast1-b
SHA=${1:-main}
echo "[cs-fix4] 创建 API 密钥（仅限 generativelanguage）"
KEY=$(gcloud services api-keys create --project "$P" --display-name="kg-lite-gemini" \
  --api-target=service=generativelanguage.googleapis.com --format='value(response.keyString)' 2>/tmp/keyerr.txt)
if [ -z "$KEY" ]; then echo "[cs-fix4] 创建失败: $(tail -3 /tmp/keyerr.txt)"; exit 1; fi
echo "[cs-fix4] 密钥已生成，长度 ${#KEY}；写入服务器"
gcloud compute ssh instance-sg --zone "$ZONE" --quiet --command "echo 'GEMINI_API_KEY=$KEY' | sudo tee -a /etc/kg-lite.env >/dev/null && sudo chmod 600 /etc/kg-lite.env && echo written" 2>&1 | grep -v -i warning
unset KEY
gcloud compute ssh instance-sg --zone "$ZONE" --quiet --command "curl -sL https://raw.githubusercontent.com/sinking88999-png/king-os/$SHA/ops/fix4.sh | sudo bash" 2>&1 | grep '^\[fix4\]'
