#!/usr/bin/env bash
# 真实调用一次 kg-lite 里的 AI（走和回复助手完全相同的代码路径）
docker exec -i deploy-kg-lite-1 python - <<'PY'
import inspect
from app import ai
from app.config import settings
print("[verify] ai_enabled =", settings.ai_enabled, "| model =", settings.gemini_model, "| vertex_project =", settings.vertex_project)
classes = [c for n, c in inspect.getmembers(ai, inspect.isclass) if c.__module__ == "app.ai"]
print("[verify] classes:", [c.__name__ for c in classes])
obj = classes[0]()
out = obj._gemini_text("客户问：我是S Pass，想换EP，最低月薪多少？用两句中文回答，不要承诺结果。")
print("[verify] AI 回复:", (out or "<None：调用失败，退回规则>")[:300])
PY
