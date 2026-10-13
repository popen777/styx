#!/usr/bin/env python3
"""Styx 2 exporter: per-user online devices and traffic for Xray and Hysteria2,
plus RU->US link health from the Xray observatory.

Metrics:
  styx_up{component}                               1 if the backend answered
  styx_user_online{node,proto,user}                VLESS: distinct online IPs, HY2: client instances
  styx_user_traffic_bytes_total{node,proto,user,direction}
  styx_awg_last_handshake_seconds{node,user,device}
  styx_outbound_alive{node,tag}                    observatory (entry node only)
  styx_outbound_delay_ms{node,tag}
"""

import json
import os
import subprocess
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NODE = os.environ.get("NODE", "unknown")
LISTEN = os.environ.get("LISTEN", "127.0.0.1:9550")
XRAY_API = os.environ.get("XRAY_API", "127.0.0.1:10085")
XRAY_METRICS = os.environ.get("XRAY_METRICS", "http://127.0.0.1:11111/debug/vars")
HY_STATS = os.environ.get("HY_STATS", "http://127.0.0.1:9998")
HY_SECRET = os.environ.get("HY_SECRET", "")
AWG_DUMP = os.environ.get("AWG_DUMP", "")
AWG_PEERS = os.environ.get("AWG_PEERS", "")
AWG_ONLINE_WINDOW = 180  # seconds since last handshake (WireGuard re-handshakes every 2 min)


def esc(v):
    return str(v).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def labels(**kw):
    return "{" + ",".join(f'{k}="{esc(v)}"' for k, v in kw.items()) + "}"


def as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def xray_users():
    res = subprocess.run(
        ["xray", "api", "statsonlineiplist", f"--server={XRAY_API}", "-all", "-include-traffic"],
        capture_output=True, timeout=10,
    )
    if res.returncode != 0:
        raise RuntimeError(res.stderr.decode(errors="replace").strip())
    out = res.stdout.decode().strip()
    return json.loads(out).get("users", []) if out else []


def http_json(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read() or b"{}")


def collect():
    lines = [
        "# HELP styx_user_online Online devices per user (VLESS: distinct IPs, HY2: client instances)",
        "# TYPE styx_user_online gauge",
    ]
    traffic = [
        "# HELP styx_user_traffic_bytes_total Per-user traffic since backend start",
        "# TYPE styx_user_traffic_bytes_total counter",
    ]
    up = ["# TYPE styx_up gauge"]

    try:
        for u in xray_users():
            name = u.get("email", "")
            ips = u.get("ips") or []
            lines.append(f"styx_user_online{labels(node=NODE, proto='vless', user=name)} {len(ips)}")
            t = u.get("traffic") or {}
            traffic.append(f"styx_user_traffic_bytes_total"
                           f"{labels(node=NODE, proto='vless', user=name, direction='up')} {as_int(t.get('uplink'))}")
            traffic.append(f"styx_user_traffic_bytes_total"
                           f"{labels(node=NODE, proto='vless', user=name, direction='down')} {as_int(t.get('downlink'))}")
        up.append(f"styx_up{labels(node=NODE, component='xray')} 1")
    except Exception as e:
        print(f"xray api: {e}")
        up.append(f"styx_up{labels(node=NODE, component='xray')} 0")

    try:
        hdr = {"Authorization": HY_SECRET} if HY_SECRET else {}
        online = http_json(f"{HY_STATS}/online", hdr)
        for name, n in online.items():
            lines.append(f"styx_user_online{labels(node=NODE, proto='hy2', user=name)} {as_int(n)}")
        for name, t in http_json(f"{HY_STATS}/traffic", hdr).items():
            # tx = server->client (client download), rx = client->server (upload)
            traffic.append(f"styx_user_traffic_bytes_total"
                           f"{labels(node=NODE, proto='hy2', user=name, direction='up')} {as_int(t.get('rx'))}")
            traffic.append(f"styx_user_traffic_bytes_total"
                           f"{labels(node=NODE, proto='hy2', user=name, direction='down')} {as_int(t.get('tx'))}")
        up.append(f"styx_up{labels(node=NODE, component='hysteria')} 1")
    except Exception as e:
        print(f"hysteria stats: {e}")
        up.append(f"styx_up{labels(node=NODE, component='hysteria')} 0")

    if AWG_DUMP and AWG_PEERS and os.path.exists(AWG_DUMP):
        try:
            with open(AWG_PEERS) as f:
                peers = json.load(f)
            online, rx_sum, tx_sum = {}, {}, {}
            hs_lines = ["# TYPE styx_awg_last_handshake_seconds gauge"]
            now = time.time()
            with open(AWG_DUMP) as f:
                for line in f:
                    parts = line.rstrip("\n").split("\t")
                    if len(parts) < 4 or parts[0] not in peers:
                        continue
                    p = peers[parts[0]]
                    user, hs = p["user"], as_int(parts[1])
                    online.setdefault(user, 0)
                    if hs and now - hs < AWG_ONLINE_WINDOW:
                        online[user] += 1
                    rx_sum[user] = rx_sum.get(user, 0) + as_int(parts[2])
                    tx_sum[user] = tx_sum.get(user, 0) + as_int(parts[3])
                    hs_lines.append(f"styx_awg_last_handshake_seconds"
                                    f"{labels(node=NODE, user=user, device=p['device'])} {hs}")
            for user, n in online.items():
                lines.append(f"styx_user_online{labels(node=NODE, proto='awg', user=user)} {n}")
                traffic.append(f"styx_user_traffic_bytes_total"
                               f"{labels(node=NODE, proto='awg', user=user, direction='up')} {rx_sum[user]}")
                traffic.append(f"styx_user_traffic_bytes_total"
                               f"{labels(node=NODE, proto='awg', user=user, direction='down')} {tx_sum[user]}")
            lines.extend(hs_lines)
            up.append(f"styx_up{labels(node=NODE, component='amneziawg')} "
                      f"{1 if now - os.path.getmtime(AWG_DUMP) < 120 else 0}")
        except Exception as e:
            print(f"awg dump: {e}")
            up.append(f"styx_up{labels(node=NODE, component='amneziawg')} 0")

    obs = ["# TYPE styx_outbound_alive gauge", "# TYPE styx_outbound_delay_ms gauge"]
    try:
        vars_ = http_json(XRAY_METRICS)
        for tag, st in (vars_.get("observatory") or {}).items():
            alive = 1 if st.get("alive") else 0
            obs.append(f"styx_outbound_alive{labels(node=NODE, tag=tag)} {alive}")
            obs.append(f"styx_outbound_delay_ms{labels(node=NODE, tag=tag)} {as_int(st.get('delay')) if alive else 0}")
    except Exception as e:
        print(f"xray metrics: {e}")

    return "\n".join(up + lines + traffic + obs) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/metrics"):
            body = collect().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
        elif self.path == "/health":
            body = b"ok\n"
            self.send_response(200)
        else:
            body = b"not found\n"
            self.send_response(404)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    host, port = LISTEN.rsplit(":", 1)
    print(f"styx-exporter node={NODE} listening on {LISTEN}")
    ThreadingHTTPServer((host, int(port)), Handler).serve_forever()
