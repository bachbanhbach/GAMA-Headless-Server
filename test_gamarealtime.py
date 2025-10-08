# gama_headless_simple.py
# pip install websockets
import asyncio
import json
import websockets
import sys

# --- Cấu hình (chỉnh theo môi trường của bạn) ---
GAMA_WS_URL = "ws://192.168.1.11:6868" #----- Chỉnh IP 
MODEL_PATH = "/workspace/pig-farm/models/simulator-01.gaml" # ---path chứa file gaml chạy
EXPERIMENT = "Normal" #---- Tên experiment

# --- Hàm phụ đơn giản: gửi payload và trả message đầu tiên server trả về ---
async def send_and_recv(ws, payload, timeout=5.0):
    await ws.send(json.dumps(payload))
    print("<< SENT:", json.dumps(payload))
    try:
        msg = await asyncio.wait_for(ws.recv(), timeout=timeout)
    except asyncio.TimeoutError:
        raise TimeoutError("Không nhận được phản hồi từ server (timeout).")
    print(">> RECV:", msg)
    try:
        return json.loads(msg)
    except Exception:
        return {"raw": msg}

# --- Luồng chính: connect, describe, load, loop step + expression, stop ---
async def main(steps: int = 10):
    async with websockets.connect(GAMA_WS_URL, ping_interval=None) as ws:
        print("✅ Connected to", GAMA_WS_URL)

        # đọc greeting nếu có (không bắt buộc)
        try:
            greeting = await asyncio.wait_for(ws.recv(), timeout=0.5)
            print(">>RECV (greeting):", greeting)
        except asyncio.TimeoutError:
            pass

        # load experiment
        load_payload = {
            "type": "load",
            "model": MODEL_PATH,
            "experiment": EXPERIMENT,
            "console": True,
            "runtime": True
        }
        load_resp = await send_and_recv(ws, load_payload)
        sim_id = load_resp.get("content")
        if sim_id is None:
            print("Không lấy được simulation id từ load response:", load_resp)
            return
        sim_id = str(sim_id)
        print(">>> Simulation ID:", sim_id)

        # step-by-step + expression
        for i in range(1, steps + 1):
            # chạy 1 bước, sync=True để đảm bảo bước hoàn tất trước khi hỏi expression
            await send_and_recv(ws, {"type": "step", "exp_id": sim_id, "nb_step": 1, "sync": True})

            # hỏi cycle
            resp_cycle = await send_and_recv(ws, {"type": "expression", "exp_id": sim_id, "expr": "cycle"})
            cycle_val = resp_cycle.get("content")

            # hỏi Pig[0].weight (có thể trả lỗi/null nếu Pig[0] không tồn tại)
            resp_w = await send_and_recv(ws, {"type": "expression", "exp_id": sim_id, "expr": "Pig[0].weight"})
            weight_val = resp_w.get("content")

            print(f"[SIMPLE] Step {i} | cycle={cycle_val} | Pig[0].weight={weight_val}")

        # stop simulation
        await send_and_recv(ws, {"type": "stop", "exp_id": sim_id})
        print("✅ Simulation stopped.")

if __name__ == "__main__":
    try:
        # thay đổi số bước ở đây nếu muốn
        asyncio.run(main(steps=3))
    except Exception as e:
        print("Exception:", e)
        sys.exit(1)
