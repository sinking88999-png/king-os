#!/usr/bin/env bash
# 只读探测：哪些 Gemini 模型名 / 地区在这个项目的 Vertex AI 上可用
PROJECT=$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)
TOKEN=$(curl -s -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
for loc in global us-central1 asia-southeast1; do
  host=aiplatform.googleapis.com; [ "$loc" != global ] && host="$loc-aiplatform.googleapis.com"
  for m in gemini-3-flash gemini-3.0-flash gemini-3-flash-lite gemini-2.5-flash gemini-2.5-flash-lite gemini-2.0-flash gemini-flash-latest gemini-3-pro gemini-2.5-pro; do
    code=$(curl -s -m 30 -o /tmp/p.json -w '%{http_code}' -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      "https://$host/v1/projects/$PROJECT/locations/$loc/publishers/google/models/$m:generateContent" \
      -d '{"contents":[{"role":"user","parts":[{"text":"回答数字：1+1="}]}]}')
    msg=$(python3 -c 'import json;d=json.load(open("/tmp/p.json"));print(("OK "+d["candidates"][0]["content"]["parts"][0]["text"].strip()) if "candidates" in d else d.get("error",{}).get("message","")[:70])' 2>/dev/null)
    echo "[probe] $loc $m -> $code $msg"
  done
done
echo "[probe] 已启用的 API: $(gcloud services list --enabled --format='value(config.name)' 2>/dev/null | grep -E 'aiplatform|generativelanguage' | tr '\n' ' ')"
