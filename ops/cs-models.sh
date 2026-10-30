#!/usr/bin/env bash
# 在 Cloud Shell 里跑：列出本项目 Vertex AI 上可用的 Gemini 模型名，并用用户身份试调一次
P=gen-lang-client-0724339507
T=$(gcloud auth print-access-token)
H=(-H "Authorization: Bearer $T" -H "x-goog-user-project: $P")
curl -s "${H[@]}" "https://us-central1-aiplatform.googleapis.com/v1beta1/publishers/google/models?pageSize=300" > /tmp/models.json
python3 - <<'PY'
import json
d = json.load(open("/tmp/models.json"))
err = d.get("error", {}).get("message", "")
names = sorted({m["name"].split("/")[-1] for m in d.get("publisherModels", []) if "gemini" in m["name"].lower()})
print(f"[models] err={err[:150]!r} count={len(names)}")
for i in range(0, len(names), 8): print("[models] " + " ".join(names[i:i+8]))
PY
BODY='{"contents":[{"role":"user","parts":[{"text":"回答数字：1+1="}]}]}'
for m in gemini-2.5-flash gemini-3-flash gemini-2.5-flash-lite; do
  code=$(curl -s -m 30 -o /tmp/p.json -w '%{http_code}' "${H[@]}" -H 'Content-Type: application/json' \
    "https://aiplatform.googleapis.com/v1/projects/$P/locations/global/publishers/google/models/$m:generateContent" -d "$BODY")
  echo "[models] user-token vertex $m -> $code $(python3 -c 'import json;d=json.load(open("/tmp/p.json"));print(("OK "+d["candidates"][0]["content"]["parts"][0]["text"].strip()) if "candidates" in d else d.get("error",{}).get("message","")[:100])' 2>/dev/null)"
done
