#!/usr/bin/env bash
# 在 Cloud Shell 跑：SSH 只允许 Google IAP 安全通道（35.235.240.0/20），先验证 IAP 可登录，再收紧；失败自动回滚
set -u
P=gen-lang-client-0724339507
say(){ echo "[up4] $*"; }
gcloud services enable iap.googleapis.com --project $P --quiet
# 先加 IAP 放行规则，再测试
gcloud compute firewall-rules describe allow-ssh-iap --project $P >/dev/null 2>&1 || \
  gcloud compute firewall-rules create allow-ssh-iap --project $P --direction=INGRESS --action=allow --rules=tcp:22 --source-ranges=35.235.240.0/20 --quiet >/dev/null
r=$(gcloud compute ssh instance-sg --zone asia-southeast1-b --tunnel-through-iap --quiet --command 'echo IAP-OK' 2>&1 | tail -1)
say "IAP 登录测试: $r"
if [ "$r" = "IAP-OK" ]; then
  gcloud compute firewall-rules update default-allow-ssh --project $P --source-ranges=35.235.240.0/20,52.76.121.120/32 --quiet >/dev/null && say "default-allow-ssh 已收紧到 IAP 网段 + GMSSH"
  r2=$(gcloud compute ssh instance-sg --zone asia-southeast1-b --tunnel-through-iap --quiet --command 'echo STILL-OK' 2>&1 | tail -1)
  say "收紧后复测: $r2"
  if [ "$r2" != "STILL-OK" ]; then gcloud compute firewall-rules update default-allow-ssh --project $P --source-ranges=0.0.0.0/0 --quiet; say "复测失败，已回滚"; fi
else
  say "IAP 不通，不收紧"
fi
gcloud compute firewall-rules list --project $P --format='csv[no-heading](name,sourceRanges.list(),allowed[].map().firewall_rule().list())' | sed 's/^/[up4] /'
say DONE
