#!/usr/bin/env bash
# fix3: kg-lite 回复助手接 Google AI（Vertex AI，用服务器自带身份，不放任何密钥）。幂等。
set -u
APP=/srv/kg-lite/app
ENVF=/etc/kg-lite.env
COMPOSE_DIR=/srv/kg-lite/deploy
STAMP=$(date +%Y%m%d-%H%M%S)
say(){ echo "[fix3] $*"; }
PROJECT=$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)
say "project=$PROJECT"

# 0) 先用服务器身份直接试一次 Vertex，确认权限（不改任何东西）
TOKEN=$(curl -s -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
probe(){ curl -s -m 40 -o /tmp/vertex-probe.json -w '%{http_code}' -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  "https://aiplatform.googleapis.com/v1/projects/$PROJECT/locations/global/publishers/google/models/$1:generateContent" \
  -d '{"contents":[{"role":"user","parts":[{"text":"用中文回答：1+1=?只回答数字"}]}]}'; }
MODEL=gemini-2.5-flash
code=$(probe $MODEL)
say "Vertex 探测 $MODEL -> HTTP $code: $(python3 -c 'import json;d=json.load(open("/tmp/vertex-probe.json"));print(d["candidates"][0]["content"]["parts"][0]["text"].strip() if "candidates" in d else d.get("error",{}).get("message","")[:160])' 2>/dev/null)"
if [ "$code" != "200" ]; then say "Vertex 不可用，停止（不改代码）"; exit 1; fi

# 1) 打补丁
cp -a "$APP/ai.py" "$APP/ai.py.bak-$STAMP"; cp -a "$APP/config.py" "$APP/config.py.bak-$STAMP"
python3 - "$APP" <<'PY'
import sys, re, pathlib
app = pathlib.Path(sys.argv[1])
cfg = app/"config.py"; ai = app/"ai.py"
c = cfg.read_text()
if "vertex_project" not in c:
    c = c.replace('        self.gemini_model = os.environ.get("GEMINI_MODEL", "gemini-flash-latest")',
'''        self.gemini_model = os.environ.get("GEMINI_MODEL", "gemini-flash-latest")
        # Vertex AI：用虚拟机自带的服务账号身份，不需要密钥（KG_VERTEX_PROJECT 非空即启用）
        self.vertex_project = os.environ.get("KG_VERTEX_PROJECT", "")
        self.vertex_location = os.environ.get("KG_VERTEX_LOCATION", "global")''')
    c = c.replace("        return bool(self.gemini_key)", "        return bool(self.gemini_key or self.vertex_project)")
    cfg.write_text(c); print("config.py patched")
a = ai.read_text()
if "_vertex_token" not in a:
    a = a.replace('GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"',
'''GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
VERTEX_URL = "https://{host}/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
_META_TOKEN = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"


def _vertex_token(client: "httpx.Client") -> str:
    r = client.get(_META_TOKEN, headers={"Metadata-Flavor": "Google"}, timeout=5)
    r.raise_for_status()
    return r.json()["access_token"]''')
    old = '''            r = client.post(GEMINI_URL.format(model=settings.gemini_model),
                            params={"key": settings.gemini_key}, json=body)'''
    new = '''            if settings.gemini_key:
                r = client.post(GEMINI_URL.format(model=settings.gemini_model),
                                params={"key": settings.gemini_key}, json=body)
            else:
                loc = settings.vertex_location
                host = "aiplatform.googleapis.com" if loc == "global" else f"{loc}-aiplatform.googleapis.com"
                r = client.post(VERTEX_URL.format(host=host, project=settings.vertex_project,
                                                  location=loc, model=settings.gemini_model),
                                headers={"Authorization": f"Bearer {_vertex_token(client)}"}, json=body)'''
    assert old in a, "call site not found"
    a = a.replace(old, new); ai.write_text(a); print("ai.py patched")
PY
python3 -m py_compile "$APP/ai.py" "$APP/config.py" && say "语法检查通过" || { say "语法错误，回滚"; cp -a "$APP/ai.py.bak-$STAMP" "$APP/ai.py"; cp -a "$APP/config.py.bak-$STAMP" "$APP/config.py"; exit 1; }

# 2) 环境变量
grep -q '^KG_VERTEX_PROJECT=' "$ENVF" || echo "KG_VERTEX_PROJECT=$PROJECT" >> "$ENVF"
grep -q '^KG_VERTEX_LOCATION=' "$ENVF" || echo "KG_VERTEX_LOCATION=global" >> "$ENVF"
sed -i "s/^GEMINI_MODEL=.*/GEMINI_MODEL=$MODEL/" "$ENVF"; grep -q '^GEMINI_MODEL=' "$ENVF" || echo "GEMINI_MODEL=$MODEL" >> "$ENVF"
say "env: $(grep -E '^(KG_VERTEX|GEMINI_MODEL)' "$ENVF" | tr '\n' ' ')"

# 3) 重建并重启
(cd "$COMPOSE_DIR" && docker compose up -d --build kg-lite 2>&1 | tail -2)
sleep 8
say "kg-lite 容器: $(docker ps --format '{{.Names}} {{.Status}}' | grep kg-lite)"
say "健康页: $(curl -s -m 10 http://127.0.0.1:8200/healthz 2>/dev/null | cut -c1-200)"
docker logs --tail 15 deploy-kg-lite-1 2>&1 | grep -iE 'error|traceback|vertex|gemini' | tail -5
say DONE
