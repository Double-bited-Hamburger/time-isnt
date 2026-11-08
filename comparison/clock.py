"""Python/tkinter version of the same clock, written only to compare it with
TimeIsnt.exe. Same features: dark theme, F11 full screen, NTP sync."""
import ctypes
import socket
import struct
import threading
import time
import tkinter as tk
from datetime import datetime

ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))

SERVERS = ["time.cloudflare.com", "time.google.com", "time.windows.com", "pool.ntp.org"]
NTP_EPOCH = 2208988800  # seconds from 1900 to 1970
BG, FG, DATE, DIM = "#0E0F12", "#E8EAED", "#8B9099", "#5C636A"

offset = 0.0
status = "Syncing with internet time…"
wake = threading.Event()


def ntp_query(sock):
    t1 = time.time()
    sock.send(b"\x23" + 47 * b"\0")
    data = sock.recv(48)
    t4 = time.time()
    if len(data) < 48 or data[0] & 7 != 4 or not 1 <= data[1] <= 15:
        return None
    s2, f2, s3, f3 = struct.unpack("!4I", data[32:48])
    t2 = s2 - NTP_EPOCH + f2 / 2**32
    t3 = s3 - NTP_EPOCH + f3 / 2**32
    return ((t2 - t1) + (t3 - t4)) / 2, (t4 - t1) - (t3 - t2)


def sync_loop():
    global offset, status
    while True:
        ok = False
        for host in SERVERS:
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                    s.settimeout(1.5)
                    s.connect((host, 123))
                    samples = [r for r in (ntp_query(s) for _ in range(4)) if r]
            except OSError:
                continue
            if samples:
                offset, delay = min(samples, key=lambda r: r[1])
                ms = abs(offset) * 1000
                status = (f"Synced · {host} · PC clock {ms:.0f} ms "
                          f"{'behind' if offset > 0 else 'ahead'} · ±{delay * 500:.0f} ms")
                ok = True
                break
        if not ok:
            status = "Can't reach time servers — showing this PC's clock"
        wake.wait(900 if ok else 30)
        wake.clear()


root = tk.Tk()
root.title("Time ISN't (Python)")
root.configure(bg=BG)
sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()
root.geometry(f"{sw * 6 // 10}x{sh * 6 // 10}+{sw // 5}+{sh // 5}")
canvas = tk.Canvas(root, bg=BG, highlightthickness=0)
canvas.pack(fill="both", expand=True)
t_item = canvas.create_text(0, 0, fill=FG, font=("Segoe UI", -100, "bold"))
d_item = canvas.create_text(0, 0, fill=DATE, font=("Segoe UI", -20))
s_item = canvas.create_text(0, 0, fill=DIM, font=("Segoe UI", -14))


def layout(event):
    w, h = event.width, event.height
    em = max(8, min(int(w * 0.86 / 4.6), int(h * 0.40 / 0.72)))
    canvas.itemconfig(t_item, font=("Segoe UI", -em, "bold"))
    canvas.itemconfig(d_item, font=("Segoe UI", -max(12, em * 14 // 100)))
    canvas.itemconfig(s_item, font=("Segoe UI", -max(12, h // 50)))
    canvas.coords(t_item, w // 2, h // 2 - em * 0.1)
    canvas.coords(d_item, w // 2, h // 2 + em * 0.55)
    canvas.coords(s_item, w // 2, h - max(12, h // 50) * 1.5)


def tick():
    now = time.time() + offset
    canvas.itemconfig(t_item, text=datetime.fromtimestamp(now).strftime("%H:%M:%S"))
    canvas.itemconfig(d_item, text=datetime.fromtimestamp(now).strftime("%d %B %Y"))
    canvas.itemconfig(s_item, text=status)
    root.after(int(1000 - (now % 1) * 1000) + 1, tick)


def toggle(_=None):
    root.attributes("-fullscreen", not root.attributes("-fullscreen"))


canvas.bind("<Configure>", layout)
root.bind("<F11>", toggle)
root.bind("<Double-Button-1>", toggle)
root.bind("<Escape>", lambda e: root.attributes("-fullscreen", False))
root.bind("s", lambda e: wake.set())
threading.Thread(target=sync_loop, daemon=True).start()
if "--full" in __import__("sys").argv:
    root.after(500, toggle)
tick()
root.mainloop()
