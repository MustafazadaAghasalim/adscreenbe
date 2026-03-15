#!/usr/bin/env python3
import time
import psutil
import serial
import serial.tools.list_ports
import sys
import os
import subprocess
import json

def find_arduino_port():
    ports = list(serial.tools.list_ports.comports())
    for p in ports:
        if "Arduino" in p.description or "USB" in p.description or "ACM" in p.name:
            return p.device
    defaults = ['/dev/ttyACM0', '/dev/ttyACM1', '/dev/ttyUSB0', '/dev/ttyUSB1']
    for p in defaults:
        if os.path.exists(p): return p
    return None

def get_cpu_temp():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
            return int(float(f.read().strip()) / 1000.0)
    except: return 0

def get_uptime():
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
            days = int(uptime_seconds // 86400)
            hours = int((uptime_seconds % 86400) // 3600)
            if days > 0:
                return f"{days}d{hours}h"
            else:
                mins = int((uptime_seconds % 3600) // 60)
                return f"{hours}h{mins}m"
    except: return "--"

def get_telemetry():
    telemetry = {}
    
    # Dashboard
    telemetry["c"] = int(psutil.cpu_percent(interval=None))
    telemetry["r"] = int(psutil.virtual_memory().percent)
    telemetry["t"] = get_cpu_temp()
    telemetry["dk"] = int(psutil.disk_usage('/').percent)
    telemetry["w"] = "OK"
    
    try:
        docker_active = subprocess.call(["systemctl", "is-active", "--quiet", "docker"]) == 0
        telemetry["d"] = "UP" if docker_active else "DWN"
    except:
        telemetry["d"] = "--"
        
    telemetry["up"] = get_uptime()
    
    try:
        telemetry["h"] = subprocess.check_output("hostname", shell=True).decode().strip()[:15]
    except:
        telemetry["h"] = "pi"

    # Server Status
    try:
        http_code = subprocess.check_output("curl -s -o /dev/null -w '%{http_code}' http://localhost || echo 0", shell=True).decode().strip()
        telemetry["ht"] = int(http_code)
    except: telemetry["ht"] = 0
    
    try:
        nginx_active = subprocess.call(["systemctl", "is-active", "--quiet", "nginx"]) == 0
        telemetry["ng"] = "UP" if nginx_active else "DWN"
    except: telemetry["ng"] = "--"
    
    telemetry["sl"] = 90  # Placeholder since openssl domain check requires an actual domain
    
    try:
        docker_running = subprocess.check_output("docker ps -q 2>/dev/null | wc -l || echo 0", shell=True).decode().strip()
        telemetry["cn"] = int(docker_running)
    except: telemetry["cn"] = 0
    
    # Network Status
    try:
        local_ip = subprocess.check_output("hostname -I | awk '{print $1}'", shell=True).decode().strip()
        telemetry["ip"] = local_ip if local_ip else "127.0.0.1"
    except: telemetry["ip"] = "0.0.0.0"
    
    try:
        public_ip = subprocess.check_output("curl -s -m 2 https://api.ipify.org || echo N/A", shell=True).decode().strip()
        telemetry["pi"] = public_ip
    except: telemetry["pi"] = "N/A"
    
    try:
        ping = subprocess.check_output("ping -c 1 -W 1 8.8.8.8 | grep time= | awk -F'time=' '{print $2}' | awk '{print $1}'", shell=True).decode().strip()
        telemetry["pg"] = ping if ping else "ERR"
    except: telemetry["pg"] = "ERR"
    
    try:
        ssh_users = subprocess.check_output("netstat -tnpa 2>/dev/null | grep 'ESTABLISHED.*sshd' | wc -l", shell=True).decode().strip()
        telemetry["ss"] = ssh_users if ssh_users else "0"
    except: telemetry["ss"] = "0"
    
    try:
        net = psutil.net_io_counters()
        telemetry["rx"] = int(net.bytes_recv / (1024*1024))
        telemetry["tx"] = int(net.bytes_sent / (1024*1024))
    except:
        telemetry["rx"] = 0
        telemetry["tx"] = 0
        
    return telemetry

def main():
    print("Starting JSON Serial Daemon for V2.0...")
    port_name = find_arduino_port()
    if not port_name:
        print("Error: Could not find Arduino.")
        sys.exit(1)
        
    try:
        ser = serial.Serial(port_name, 115200, timeout=0.1)
        time.sleep(2)
        print(f"Connected to Arduino on {port_name}.")
        
        psutil.cpu_percent()
        last_send_time = 0
        update_interval = 1.0 # 1s updates
        buffer = ""
        
        while True:
            # 1. Listen for requests from Arduino
            if ser.in_waiting:
                chunk = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
                buffer += chunk
                
                while '<' in buffer and '>' in buffer:
                    start = buffer.find('<')
                    end = buffer.find('>', start)
                    if end != -1:
                        msg = buffer[start+1:end]
                        buffer = buffer[end+1:]
                        try:
                            data = json.loads(msg)
                            print(f"Received JSON: {data}")
                            cmd = data.get("cmd")
                            
                            if cmd == "request_data":
                                last_send_time = 0
                            elif cmd == "reboot_pi":
                                ser.write(b'<{"ack":"ok","msg":"Rebooting..."}>\n')
                                os.system("sudo reboot")
                            elif cmd == "shutdown_pi":
                                ser.write(b'<{"ack":"ok","msg":"Shutting down..."}>\n')
                                os.system("sudo poweroff")
                            elif cmd == "restart_docker":
                                ser.write(b'<{"ack":"ok","msg":"Restart Docker"}>\n')
                                os.system("sudo systemctl restart docker")
                            elif cmd == "restart_service":
                                target = data.get("target", "service")
                                ser.write(f'<{"{"}"ack":"ok","msg":"Restart {target}"{"}"}>\n'.encode())
                                os.system(f"sudo systemctl restart {target}")
                            elif cmd == "clear_cache":
                                ser.write(b'<{"ack":"ok","msg":"Cache Cleared"}>\n')
                                os.system("sudo sysctl -w vm.drop_caches=3")
                            elif cmd == "update_os":
                                ser.write(b'<{"ack":"ok","msg":"Updating OS..."}>\n')
                                os.system("sudo apt-get update > /dev/null 2>&1 &")
                            elif cmd == "ping_test":
                                ser.write(b'<{"ack":"ok","msg":"Ping Test"}>\n')
                        except Exception as e: pass
                    else:
                        break
            
            # 2. Send Data periodically
            current_time = time.time()
            if current_time - last_send_time >= update_interval:
                telemetry = get_telemetry()
                payload = "<" + json.dumps(telemetry) + ">\n"
                ser.write(payload.encode('utf-8'))
                last_send_time = current_time
                
            time.sleep(0.05)
            
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == "__main__":
    main()
