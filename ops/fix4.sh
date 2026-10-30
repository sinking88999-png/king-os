#!/usr/bin/env bash
# fix4: /etc/kg-lite.env 里已放入 GEMINI_API_KEY 后，验证密钥可用并重启 kg-lite。幂等。不打印密钥。
set -u
ENVF=/etc/kg-lite.env
COMPOSE_DIR=/srv/kg-lite/deploy
say(){ echo "[fix4] $*"; }
KEY=$(grep -E '^GEMINI_API_KEY=' "$ENVF" | tail -1 | cut -d= -f2-)
[ -n "$KEY" ] || { say "env 里没有 GEMINI_API_KEY，停止"; exit 1; }
say "密钥长度 ${#KEY}"
MODEL=$(grep -E '^GEMINI_MODEL=' "$ENVF" | tail -1 | cut -d= -f2-); MODEL=${MODEL:-gemini-flash-latest}
BODY='{"contents":[{"role":"user","parts":[{"text":"用一句话中文回答：新加坡EP准证是什么？"}]}]}'
code=$(curl -s -m 40 -o /tmp/g.json -w '%{http_code}' -H 'Content-Type: application/json' \
  "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$KEY" -d "$BODY")
say "Gemini 直连 $MODEL -> HTTP $code: $(python3 -c 'import json;d=json.load(open("/tmp/g.json"));print(d["candidates"][0]["content"]["parts"][0]["text"].strip()[:120] if "candidates" in d else d.get("error",{}).get("message","")[:160])' 2>/dev/null)"
[ "$code" = 200 ] || { say "密钥不可用，停止"; exit 1; }
# 去掉重复的 GEMINI_API_KEY 行（只留最后一条）
python3 - "$ENVF" <<'PY'
import sys
p=sys.argv[1]; lines=open(p).read().splitlines()
keys=[l for l in lines if l.startswith("GEMINI_API_KEY=")]
if len(keys)>1:
    last=keys[-1]; out=[l for l in lines if not l.startswith("GEMINI_API_KEY=")]+[last]
    open(p,"w").write("\n".join(out)+"\n")
PY
chmod 600 "$ENVF"
(cd "$COMPOSE_DIR" && docker compose up -d --force-recreate kg-lite 2>&1 | tail -1)
sleep 8
say "容器: $(docker ps --format '{{.Names}} {{.Status}}' | grep kg-lite)"
say "健康页: $(curl -s -m 10 http://127.0.0.1:8200/healthz 2>/dev/null | cut -c1-200)"
say "外网: $(curl -s -o /dev/null -m 15 -w '%{http_code}' https://kg.136-85-62-199.sslip.io/healthz)"
say DONE
