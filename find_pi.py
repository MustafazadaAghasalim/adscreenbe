#!/usr/bin/env python3
"""Scan network for Raspberry Pi with SSH enabled."""
import socket
import concurrent.futures
import time
import subprocess

def check_ssh(ip):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.5)
        result = s.connect_ex((ip, 22))
        s.close()
        if result == 0:
            return ip
    except Exception:
        pass
    return None

def main():
    found = []
    
    # Try hostname resolution first
    print("=== Trying hostname resolution ===")
    for host in ['zynorex', 'zynorex.local', 'raspberrypi', 'raspberrypi.local']:
        try:
            ip = socket.gethostbyname(host)
            print(f"  Resolved {host} -> {ip}")
            found.append(ip)
        except Exception:
            print(f"  {host}: not found")
    
    # Scan entire 169.254.x.x/16 for SSH
    print("\n=== Scanning 169.254.x.x/16 for SSH (port 22) ===")
    start = time.time()
    ips = [f"169.254.{a}.{b}" for a in range(0, 256) for b in range(1, 255)]
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=500) as executor:
        futures = {executor.submit(check_ssh, ip): ip for ip in ips}
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result and result != "169.254.223.155":
                found.append(result)
                print(f"  FOUND SSH: {result}")
    
    elapsed = time.time() - start
    print(f"  Scanned {len(ips)} IPs in {elapsed:.1f}s")
    
    # Scan 10.10.0.0/22 for SSH
    print("\n=== Scanning 10.10.0.0/22 for SSH ===")
    start = time.time()
    ips2 = [f"10.10.{a}.{b}" for a in range(0, 4) for b in range(1, 255)]
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=300) as executor:
        futures = {executor.submit(check_ssh, ip): ip for ip in ips2}
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result and result != "10.10.3.61":
                found.append(result)
                print(f"  FOUND SSH: {result}")
    
    elapsed = time.time() - start
    print(f"  Scanned {len(ips2)} IPs in {elapsed:.1f}s")
    
    print(f"\n=== RESULTS ===")
    if found:
        print(f"Found SSH-enabled devices: {found}")
    else:
        print("No Raspberry Pi found on the network.")
        print("\nPossible issues:")
        print("  1. Pi is not powered on or still booting")
        print("  2. SSH is not enabled on the Pi (disabled by default)")
        print("  3. SD card doesn't have Raspberry Pi OS installed")
        print("  4. Network cable not properly connected")

if __name__ == "__main__":
    main()
