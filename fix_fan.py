import re

with open("/home/zynorex/adscreen-website/server.js", "r") as f:
    content = f.read()

changes = 0

# 1. Add fan_mode_raw and nvme_temp reads after fanPwm line in telemetry
old1 = 'const fanPwm = shellRun("cat /sys/class/hwmon/hwmon3/pwm1 2>/dev/null || cat /sys/class/hwmon/hwmon1/pwm1 2>/dev/null");'
new1 = old1 + '''
        const fanPwmEnable = shellRun("cat /sys/class/hwmon/hwmon3/pwm1_enable 2>/dev/null || cat /sys/class/hwmon/hwmon1/pwm1_enable 2>/dev/null");
        const nvmeTemp = shellRun("cat /sys/class/hwmon/hwmon1/temp1_input 2>/dev/null");'''
if old1 in content:
    content = content.replace(old1, new1, 1)
    changes += 1
    print("1. Added fanPwmEnable + nvmeTemp reads")

# 2. Add fan.mode and nvme_temp_c to telemetry output
old2 = '''percent: fanPwm ? Math.round((parseInt(fanPwm) / 255) * 100) : null,
            },
            uptime: uptimeRaw || null,'''
new2 = '''percent: fanPwm ? Math.round((parseInt(fanPwm) / 255) * 100) : null,
                mode: fanPwmEnable === "2" ? "auto" : fanPwmEnable === "1" ? "manual" : "off",
            },
            nvme_temp_c: nvmeTemp ? (parseInt(nvmeTemp) / 1000).toFixed(1) : null,
            uptime: uptimeRaw || null,'''
if old2 in content:
    content = content.replace(old2, new2, 1)
    changes += 1
    print("2. Added fan.mode + nvme_temp_c to telemetry")

# 3. Add fan_mode to GET /api/pi/fan response
old3 = '''fan_rpm: fanRpm ? parseInt(fanRpm) : null,
        });'''
new3 = '''fan_rpm: fanRpm ? parseInt(fanRpm) : null,
            fan_mode: (() => { const e = run("cat /sys/class/hwmon/hwmon3/pwm1_enable 2>/dev/null"); return e === "2" ? "auto" : e === "1" ? "manual" : "off"; })(),
        });'''
if old3 in content:
    content = content.replace(old3, new3, 1)
    changes += 1
    print("3. Added fan_mode to GET /api/pi/fan")

# 4. Add RPM to POST /api/pi/fan manual mode response
old4 = "res.json({ status: 'success', pwm, percent: Math.round((pwm / 255) * 100) });"
new4 = '''const rpmAfter = run("cat /sys/class/hwmon/hwmon3/fan1_input 2>/dev/null || echo 0");
        res.json({ status: 'success', pwm, percent: Math.round((pwm / 255) * 100), rpm: parseInt(rpmAfter) || 0, mode: 'manual' });'''
if old4 in content:
    content = content.replace(old4, new4, 1)
    changes += 1
    print("4. Added RPM to POST /api/pi/fan response")

with open("/home/zynorex/adscreen-website/server.js", "w") as f:
    f.write(content)
print(f"\nTotal changes: {changes}")
