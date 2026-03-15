#!/usr/bin/env python3
"""Try SSH login with admin/destroyer on all found IPs to identify the Pi."""
import subprocess
import sys

ips = [
    '10.10.0.80', '10.10.0.7', '10.10.0.2', '10.10.0.9', '10.10.0.8',
    '10.10.0.4', '10.10.0.3', '10.10.0.5', '10.10.0.6', '10.10.1.188', '10.10.2.4'
]

for ip in ips:
    print(f"Trying {ip}...", end=" ", flush=True)
    try:
        result = subprocess.run(
            ['sshpass', '-p', 'destroyer', 'ssh',
             '-o', 'StrictHostKeyChecking=no',
             '-o', 'ConnectTimeout=3',
             f'admin@{ip}', 'hostname && uname -m'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            output = result.stdout.strip()
            print(f"SUCCESS! -> {output}")
            if 'aarch64' in output or 'arm' in output or 'webserver' in output.lower():
                print(f"\n*** RASPBERRY PI FOUND AT {ip} ***")
                print(f"    Hostname: {output}")
                sys.exit(0)
        else:
            print(f"failed (rc={result.returncode})")
    except subprocess.TimeoutExpired:
        print("timeout")
    except Exception as e:
        print(f"error: {e}")

print("\nNo Pi found with admin/destroyer credentials on any IP")
