#!/usr/bin/env bash
# 在 Cloud Shell 里跑：用用户身份逐个试调目录里的 Gemini flash 模型，找出本项目真正能用的名字
P=gen-lang-client-0724339507
T=$(gcloud auth print-access-token)
H=(-H "Authorization: Bearer $T" -H "x-goog-user-project: $P" -H 'Content-Type: application/json')
BODY='{"contents":[{"role":"user","parts":[{"text":"回答数字：1+1="}]}]}'
for loc in global us-central1 asia-southeast1; do
  host=aiplatform.googleapis.com; [ "$loc" != global ] && host="$loc-aiplatform.googleapis.com"
  for m in gemini-3.8-flash gemini-3.7-flash gemini-3.6-flash gemini-3.5-flash gemini-3.5-flash-lite gemini-3.1-flash-lite gemini-3-flash-preview gemini-2.5-flash; do
    code=$(curl -s -m 30 -o /tmp/p.json -w '%{http_code}' "${H[@]}" \
      "https://$host/v1/projects/$P/locations/$loc/publishers/google/models/$m:generateContent" -d "$BODY")
    echo "[models] $loc $m -> $code $(python3 -c 'import json;d=json.load(open("/tmp/p.json"));print(("OK "+d["candidates"][0]["content"]["parts"][0]["text"].strip()) if "candidates" in d else d.get("error",{}).get("message","")[:60])' 2>/dev/null)"
    [ "$code" = 200 ] && break
  done
done
