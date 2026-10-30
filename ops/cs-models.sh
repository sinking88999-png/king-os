#!/usr/bin/env bash
# 在 Cloud Shell 里跑：列出本项目 Vertex AI 上可用的 Gemini 模型名
T=$(gcloud auth print-access-token)
for loc in us-central1 global; do
  host=aiplatform.googleapis.com; [ "$loc" != global ] && host="$loc-aiplatform.googleapis.com"
  curl -s -H "Authorization: Bearer $T" "https://$host/v1beta1/publishers/google/models?pageSize=300" > /tmp/models.json
  python3 - "$loc" <<'PY'
import sys, json
loc = sys.argv[1]
d = json.load(open("/tmp/models.json"))
err = d.get("error", {}).get("message", "")
names = sorted({m["name"].split("/")[-1] for m in d.get("publisherModels", []) if "gemini" in m["name"]})
print(f"[models] {loc} err={err[:120]!r} count={len(names)}")
print("[models] " + " ".join(names))
PY
done
