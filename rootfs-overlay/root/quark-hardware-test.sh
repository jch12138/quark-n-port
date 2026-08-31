#!/bin/bash
set -uo pipefail

INTERACTIVE=0
if [ "${1:-}" = "--interactive" ]; then
	INTERACTIVE=1
elif [ "$#" -ne 0 ]; then
	echo "usage: $0 [--interactive]" >&2
	exit 2
fi

if [ "${QUARK_TEST_LOGGED:-0}" -eq 0 ]; then
	REPORT="/root/quark-hardware-report-$(date +%Y%m%d-%H%M%S).txt"
	QUARK_TEST_LOGGED=1 "$0" "$@" 2>&1 | tee "$REPORT"
	STATUS=${PIPESTATUS[0]}
	echo
	echo "Report saved to $REPORT"
	exit "$STATUS"
fi

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() {
	PASS_COUNT=$((PASS_COUNT + 1))
	printf '[PASS] %s\n' "$*"
}

warn() {
	WARN_COUNT=$((WARN_COUNT + 1))
	printf '[WARN] %s\n' "$*"
}

fail() {
	FAIL_COUNT=$((FAIL_COUNT + 1))
	printf '[FAIL] %s\n' "$*"
}

section() {
	printf '\n== %s ==\n' "$*"
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

section "System"
echo "Kernel: $(uname -srmo)"
echo "Uptime: $(uptime -p 2>/dev/null || cut -d. -f1 /proc/uptime)"
awk '/MemTotal/ { printf "Memory: %.0f MiB\n", $2 / 1024 }' /proc/meminfo
if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
	TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
	echo "CPU temperature: $((TEMP / 1000)) C"
	pass "thermal sensor"
else
	warn "thermal sensor is unavailable"
fi

section "Storage"
ROOT_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || true)
echo "Root filesystem: ${ROOT_SOURCE:-unknown}"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
if [ -b /dev/mmcblk0 ] && [ -b /dev/mmcblk0p2 ]; then
	pass "MicroSD and root partition detected"
else
	fail "MicroSD/root partition missing"
fi
if [ -b /dev/mmcblk2 ]; then
	if dd if=/dev/mmcblk2 of=/dev/null bs=512 count=1 status=none; then
		pass "eMMC detected and readable"
	else
	fail "eMMC exists but cannot be read"
	fi
else
	fail "eMMC is not detected"
fi

section "Display and GPU"
if [ -r /sys/class/graphics/fb0/virtual_size ]; then
	FB_SIZE=$(cat /sys/class/graphics/fb0/virtual_size)
	echo "Framebuffer: $FB_SIZE"
	[ "$FB_SIZE" = "240,135" ] && pass "ST7789 framebuffer geometry" || fail "unexpected framebuffer geometry"
else
	fail "fb0 is missing"
fi
if [ -e /dev/dri/renderD128 ]; then
	pass "Lima render node"
else
	fail "GPU render node is missing"
fi

section "Serial console and SSH"
systemctl is-active --quiet serial-getty@ttyS0.service && pass "serial getty" || fail "serial getty is not active"
if sshd -T 2>/dev/null | grep -i '^PermitRootLogin yes$' >/dev/null; then
	pass "root SSH login policy"
else
	fail "root SSH login is not enabled"
fi

section "Wi-Fi"
WLAN_IF=""
for NET_PATH in /sys/class/net/*; do
	if [ -d "$NET_PATH/wireless" ]; then
		WLAN_IF=${NET_PATH##*/}
		break
	fi
done
if [ -n "$WLAN_IF" ]; then
	echo "Interface: $WLAN_IF"
	ip -4 -br address show dev "$WLAN_IF" 2>/dev/null || true
	if ip -4 address show dev "$WLAN_IF" | grep 'inet ' >/dev/null; then
		pass "Wi-Fi interface has an IPv4 address"
	else
		warn "Wi-Fi interface exists but has no IPv4 address"
	fi
else
	fail "wireless interface is missing"
fi

section "Bluetooth"
if [ -e /sys/class/bluetooth/hci0 ]; then
	pass "Bluetooth HCI controller"
	if command_exists bluetoothctl; then
		bluetoothctl power on >/dev/null 2>&1 || true
		if bluetoothctl show 2>/dev/null | grep 'Powered: yes' >/dev/null; then
			pass "BlueZ controller powered"
		else
			warn "BlueZ sees hci0 but it is not powered"
		fi
	else
		warn "bluetoothctl is not installed"
	fi
else
	fail "Bluetooth hci0 is missing"
fi

section "Audio"
if grep -q 'H3 Audio Codec' /proc/asound/cards 2>/dev/null; then
	pass "H3 ALSA card"
else
	fail "H3 ALSA card is missing"
fi
if grep -q 'playback 1.*capture 1' /proc/asound/pcm 2>/dev/null; then
	pass "audio playback and capture PCM"
else
	fail "audio PCM directions are incomplete"
fi
if [ "$INTERACTIVE" -eq 1 ] && command_exists arecord && command_exists aplay; then
	echo "Recording the onboard microphone for 3 seconds, then playing it back..."
	if arecord -q -D hw:0,0 -f S16_LE -r 48000 -c 1 -d 3 /tmp/quark-mic-test.wav &&
	   aplay -q -D hw:0,0 /tmp/quark-mic-test.wav; then
		pass "audio DMA record/playback"
	else
		fail "audio record/playback command failed"
	fi
fi

section "MPU6050"
MPU_IIO=""
for IIO_PATH in /sys/bus/iio/devices/iio:device*; do
	[ -r "$IIO_PATH/name" ] || continue
	case "$(cat "$IIO_PATH/name")" in
		*mpu6050*) MPU_IIO=$IIO_PATH; break ;;
	esac
done
if [ -n "$MPU_IIO" ]; then
	pass "MPU6050 IIO device on I2C0"
	for VALUE in "$MPU_IIO"/in_accel_*_raw "$MPU_IIO"/in_anglvel_*_raw; do
		[ -r "$VALUE" ] && printf '%s=%s\n' "${VALUE##*/}" "$(cat "$VALUE")"
	done
elif command_exists i2cget; then
	WHO_AM_I=$(i2cget -y -f 0 0x68 0x75 b 2>/dev/null || true)
	if [ "$WHO_AM_I" = "0x68" ]; then
		warn "MPU6050 replies on I2C0 but the kernel driver did not bind"
	else
		fail "MPU6050 does not acknowledge on I2C0 address 0x68"
	fi
else
	fail "MPU6050 IIO device missing and i2cget unavailable"
fi

section "USB"
if command_exists lsusb; then
	lsusb
else
	for USB_PATH in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
		[ -r "$USB_PATH/product" ] && echo "${USB_PATH##*/}: $(cat "$USB_PATH/product")"
	done
fi
KERNEL_CONFIG=/boot/config-quark-n
if [ -r "$KERNEL_CONFIG" ]; then
	for OPTION in USB_STORAGE USB_ACM USB_SERIAL USB_VIDEO_CLASS SND_USB_AUDIO USB_CONFIGFS; do
		if grep -q "^CONFIG_${OPTION}=y$" "$KERNEL_CONFIG"; then
			pass "CONFIG_$OPTION"
		else
			fail "CONFIG_$OPTION is not built in"
		fi
	done
else
	warn "kernel config snapshot is missing"
fi

section "Buttons and LEDs"
KEY_EVENT=""
KEY_HANDLER=$(awk '
	/N: Name="gpio-keys"/ { found = 1; next }
	found && /H: Handlers=/ {
		for (i = 1; i <= NF; i++)
			if ($i ~ /^event[0-9]+$/) { print $i; exit }
	}
	found && /^$/ { exit }
' /proc/bus/input/devices 2>/dev/null)
[ -n "$KEY_HANDLER" ] && KEY_EVENT=/dev/input/$KEY_HANDLER
[ -n "$KEY_EVENT" ] && pass "GPIO power key input ($KEY_EVENT)" || warn "GPIO key event device not identified"
LED_COUNT=0
for LED_PATH in /sys/class/leds/*; do
	[ -e "$LED_PATH" ] || continue
	LED_COUNT=$((LED_COUNT + 1))
	echo "${LED_PATH##*/}: brightness=$(cat "$LED_PATH/brightness" 2>/dev/null || echo '?')"
done
[ "$LED_COUNT" -ge 2 ] && pass "board LED class devices" || warn "expected board LEDs are missing"

if [ "$INTERACTIVE" -eq 1 ]; then
	if [ -n "$KEY_EVENT" ]; then
		echo "Press the board key within 10 seconds..."
		timeout 10 evtest "$KEY_EVENT" || true
	fi
	STATUS_LED=/sys/class/leds/nanopi:blue:status
	if [ -w "$STATUS_LED/brightness" ]; then
		OLD_TRIGGER=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$STATUS_LED/trigger")
		echo none > "$STATUS_LED/trigger"
		for _ in 1 2 3; do
			echo 1 > "$STATUS_LED/brightness"
			sleep 0.3
			echo 0 > "$STATUS_LED/brightness"
			sleep 0.3
		done
		[ -n "$OLD_TRIGGER" ] && echo "$OLD_TRIGGER" > "$STATUS_LED/trigger"
		pass "interactive status LED blink completed"
	fi
fi

section "Ethernet and unresolved hardware"
if [ -e /sys/class/net/eth0 ]; then
	ip -br address show dev eth0 2>/dev/null || true
	pass "Ethernet interface"
else
	warn "no eth0; Atom-N factory DT disables EMAC and a PHY is not confirmed"
fi

section "Summary"
printf 'PASS=%d WARN=%d FAIL=%d\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
