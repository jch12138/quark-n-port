#!/bin/bash
# wifi-connect.sh <SSID> [PASSWORD]
# 连接 WiFi 并自动获取 IP。无密码的开放网络省略 PASSWORD。
# 用法示例:
#   wifi-connect.sh "MyWiFi" "mypassword"
#   wifi-connect.sh "OpenAP"

set -u

SSID="${1:-}"
PASS="${2:-}"

[ -z "$SSID" ] && { echo "用法: wifi-connect.sh <SSID> [PASSWORD]"; exit 1; }

find_wifi_iface() {
    local path
    for path in /sys/class/net/*; do
        [ -d "$path/wireless" ] && basename "$path" && return 0
    done
    return 1
}

IFACE=$(find_wifi_iface || true)
if [ -z "$IFACE" ] && [ -x /usr/local/sbin/wifi-hw-init.sh ]; then
    /usr/local/sbin/wifi-hw-init.sh
    IFACE=$(find_wifi_iface || true)
fi

[ -z "$IFACE" ] && { echo "未找到无线网卡；请检查 rtl8723bu 固件和内核日志。"; exit 1; }

echo "连接 $SSID (接口 $IFACE)..."
ip link set "$IFACE" up

if command -v iwctl >/dev/null 2>&1; then
    systemctl reset-failed iwd.service 2>/dev/null || true
    systemctl start iwd.service

    if [ -n "$PASS" ]; then
        iwctl --passphrase "$PASS" station "$IFACE" connect "$SSID"
    else
        iwctl station "$IFACE" connect "$SSID"
    fi

    for _ in $(seq 1 30); do
        if ip -4 addr show dev "$IFACE" | grep -q 'inet '; then
            echo "已连接，IP:"
            ip -4 addr show dev "$IFACE" | grep 'inet '
            exit 0
        fi
        sleep 1
    done

    echo "已关联 WiFi，但 30 秒内没有获得 IPv4 地址。" >&2
    exit 1
fi

echo "缺少 iwctl；请确认 iwd 软件包已正确安装。" >&2
exit 1
