#!/usr/bin/env bash
# 只读探测：服务器身份能否调用 Google AI（Vertex 与 Gemini API 两条路）
PROJECT=$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)
TOKEN=$(curl -s -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
show(){ python3 -c 'import json;d=json.load(open("/tmp/p.json"));print(("OK "+d["candidates"][0]["content"]["parts"][0]["text"].strip()) if "candidates" in d else d.get("error",{}).get("message","")[:90])' 2>/dev/null; }
BODY='{"contents":[{"role":"user","parts":[{"text":"回答数字：1+1="}]}]}'
for m in gemini-flash-latest gemini-2.5-flash gemini-3-flash gemini-flash-lite-latest; do
  code=$(curl -s -m 30 -o /tmp/p.json -w '%{http_code}' -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" -H 'Content-Type: application/json' \
    "https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent" -d "$BODY")
  echo "[probe] geminiapi $m -> $code $(show)"
done
for m in gemini-2.5-flash gemini-3-flash; do
  code=$(curl -s -m 30 -o /tmp/p.json -w '%{http_code}' -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    "https://aiplatform.googleapis.com/v1/projects/$PROJECT/locations/global/publishers/google/models/$m:generateContent" -d "$BODY")
  echo "[probe] vertex $m -> $code $(show)"
done
code=$(curl -s -m 30 -o /tmp/p.json -w '%{http_code}' -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" "https://generativelanguage.googleapis.com/v1beta/models?pageSize=50")
echo "[probe] 模型列表 -> $code $(python3 -c 'import json;d=json.load(open("/tmp/p.json"));print(" ".join(m["name"].split("/")[-1] for m in d.get("models",[]) if "flash" in m["name"]))' 2>/dev/null | cut -c1-300)"
