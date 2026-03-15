#!/usr/bin/env python3
"""Connect to Wetty via socket.io and execute a command to unban SSH"""
import json
import http.client
import time

HOST = "10.10.1.33"
PORT = 3002

def sio_poll(sid, data=None):
    """Socket.io long-polling transport"""
    conn = http.client.HTTPConnection(HOST, PORT, timeout=10)
    path = f"/socket.io/?EIO=4&transport=polling&sid={sid}"
    if data:
        conn.request("POST", path, body=data, headers={"Content-Type": "text/plain;charset=UTF-8"})
    else:
        conn.request("GET", path)
    resp = conn.getresponse()
    body = resp.read().decode('utf-8', errors='replace')
    conn.close()
    return body

# Step 1: Handshake
conn = http.client.HTTPConnection(HOST, PORT, timeout=10)
conn.request("GET", "/socket.io/?EIO=4&transport=polling")
resp = conn.getresponse()
raw = resp.read().decode('utf-8', errors='replace')
conn.close()
print(f"[Handshake] {raw[:200]}")

# Parse sid from response like: 0{"sid":"xxx",...}
# Engine.IO prepends message length, extract JSON
idx = raw.find('{')
if idx < 0:
    print("Failed to parse handshake")
    exit(1)
handshake = json.loads(raw[idx:raw.rindex('}')+1])
sid = handshake['sid']
print(f"[SID] {sid}")

# Step 2: Send socket.io CONNECT (namespace /)
# In EIO4, you send "40" to connect to default namespace
resp = sio_poll(sid, "40")
print(f"[Connect] {resp[:200]}")

time.sleep(1)

# Step 3: Poll for output (should get login prompt or shell)
resp = sio_poll(sid)
print(f"[Poll1] {resp[:300]}")

time.sleep(2)

# Try sending login credentials if needed
# Wetty typically auto-connects to SSH on localhost
# If it shows a login prompt, we need to type username\n then password\n

# Step 4: Send terminal input - try typing username
# socket.io event format: 42["input","text\n"]
cmd_user = '42["input","zynorex\\n"]'
resp = sio_poll(sid, cmd_user)
print(f"[SendUser] {resp[:200]}")

time.sleep(2)
resp = sio_poll(sid)
print(f"[Poll2] {resp[:300]}")

# Send password
cmd_pass = '42["input","15261526\\n"]'
resp = sio_poll(sid, cmd_pass)
print(f"[SendPass] {resp[:200]}")

time.sleep(2)
resp = sio_poll(sid)
print(f"[Poll3] {resp[:300]}")

# Now try the unban command
cmd = '42["input","sudo fail2ban-client unban --all\\n"]'
resp = sio_poll(sid, cmd)
print(f"[SendUnban] {resp[:200]}")

time.sleep(2)
resp = sio_poll(sid)
print(f"[Poll4] {resp[:300]}")

# Also restart sshd just in case
cmd2 = '42["input","sudo systemctl restart ssh\\n"]'
resp = sio_poll(sid, cmd2)
print(f"[SendSSH] {resp[:200]}")

time.sleep(2)
resp = sio_poll(sid)
print(f"[Poll5] {resp[:300]}")

print("\n[Done] Check SSH now")
