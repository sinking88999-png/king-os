#!/usr/bin/env bash
# 在 Cloud Shell 跑：Cloud Monitoring 免费拨测 + 邮件告警（站点连续 2 次检测失败就发邮件）。幂等。
set -u
P=gen-lang-client-0724339507
EMAIL=sinking88999@gmail.com
say(){ echo "[up3] $*"; }
gcloud services enable monitoring.googleapis.com --project $P --quiet
CH=$(gcloud beta monitoring channels list --project $P --filter="labels.email_address=$EMAIL" --format='value(name)' | head -1)
[ -n "$CH" ] || CH=$(gcloud beta monitoring channels create --project $P --display-name="网站告警 $EMAIL" --type=email --channel-labels=email_address=$EMAIL --format='value(name)')
say "通知渠道: $CH"
for host in www.sghitp.com kg.sghitp.com sgjike.com; do
  name="up-$host"
  path=/; [ "$host" = kg.sghitp.com ] && path=/healthz
  if ! gcloud monitoring uptime list-configs --project $P --format='value(displayName)' | grep -qx "$name"; then
    gcloud monitoring uptime create "$name" --project $P --resource-type=uptime-url \
      --resource-labels=host=$host,project_id=$P --protocol=https --path=$path --port=443 \
      --period=5 --timeout=10 --validate-ssl=true --status-classes=2xx,3xx --quiet >/dev/null && say "已建拨测 $name"
  else say "拨测已存在 $name"; fi
done
if ! gcloud alpha monitoring policies list --project $P --format='value(displayName)' | grep -qx "网站不可用"; then
cat > /tmp/policy.json <<J
{
  "displayName": "网站不可用",
  "combiner": "OR",
  "conditions": [{
    "displayName": "拨测失败",
    "conditionThreshold": {
      "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\"",
      "aggregations": [{"alignmentPeriod": "600s", "perSeriesAligner": "ALIGN_NEXT_OLDER", "crossSeriesReducer": "REDUCE_COUNT_FALSE", "groupByFields": ["resource.label.host"]}],
      "comparison": "COMPARISON_GT", "thresholdValue": 1, "duration": "300s",
      "trigger": {"count": 1}
    }
  }],
  "notificationChannels": ["$CH"],
  "documentation": {"content": "有网站连续检测失败。Claude 会处理；如需人工，可在 Google Cloud 控制台 Monitoring 查看。", "mimeType": "text/markdown"}
}
J
gcloud alpha monitoring policies create --project $P --policy-from-file=/tmp/policy.json --quiet >/dev/null && say "已建告警策略"
else say "告警策略已存在"; fi
say "拨测列表: $(gcloud monitoring uptime list-configs --project $P --format='value(displayName)' | tr '\n' ' ')"
say DONE
