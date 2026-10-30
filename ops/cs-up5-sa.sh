#!/usr/bin/env bash
# 在 Cloud Shell 跑（凌晨）：instance-sg 换成最小权限专用身份 kg-runtime。需要停机约 1-2 分钟。
set -u
P=gen-lang-client-0724339507; Z=asia-southeast1-b; VM=instance-sg
SA=kg-runtime@$P.iam.gserviceaccount.com
BUCKET=kg-lite-backup-0724339507
say(){ echo "[up5] $*"; }
gcloud iam service-accounts describe $SA --project $P >/dev/null 2>&1 || \
  gcloud iam service-accounts create kg-runtime --project $P --display-name="instance-sg 运行身份（最小权限）" --quiet
for r in roles/aiplatform.user roles/logging.logWriter roles/monitoring.metricWriter; do
  gcloud projects add-iam-policy-binding $P --member=serviceAccount:$SA --role=$r --condition=None --quiet >/dev/null && say "授予 $r"
done
gcloud storage buckets add-iam-policy-binding gs://$BUCKET --member=serviceAccount:$SA --role=roles/storage.objectAdmin --quiet >/dev/null && say "授予备份桶读写"
gcloud storage buckets add-iam-policy-binding gs://$BUCKET --member=serviceAccount:$SA --role=roles/storage.legacyBucketReader --quiet >/dev/null
say "停机切换开始 $(date -Is)"
gcloud compute instances stop $VM --zone $Z --quiet >/dev/null
gcloud compute instances set-service-account $VM --zone $Z --service-account=$SA --scopes=cloud-platform --quiet >/dev/null
gcloud compute instances start $VM --zone $Z --quiet >/dev/null
say "已开机 $(date -Is)，等待服务"
sleep 60
for h in www.sghitp.com kg.sghitp.com sgjike.com growth.sghitp.com; do say "$h -> $(curl -s -o /dev/null -m 20 -w '%{http_code}' https://$h/)"; done
say "AI: $(curl -s -m 20 https://kg.sghitp.com/healthz)"
gcloud compute ssh $VM --zone $Z --tunnel-through-iap --quiet --command 'echo "[up5] 新身份: $(curl -s -H Metadata-Flavor:Google http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email)"; sudo docker exec deploy-kg-lite-1 python -c "from app.ai import Assistant;print(\"[up5] AI 实测:\",(Assistant()._gemini_text(\"回答数字：1+1=\") or \"失败\")[:40])"; sudo /usr/local/bin/kg-backup-sync.sh; echo "[up5] 备份上传: $(tail -1 /var/log/kg-backup-sync.log)"; echo "[up5] 开机后服务: caddy=$(systemctl is-active caddy) jike=$(systemctl is-active jike 2>/dev/null) 容器=$(sudo docker ps -q | wc -l)"' 2>&1 | grep '^\[up5\]'
say DONE
