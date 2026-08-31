#!/bin/bash
# Retry RTL8723BU probing after the root filesystem (and its firmware) is available.
set -u

find_wifi_iface() {
    local path
    for path in /sys/class/net/*; do
        [ -d "$path/wireless" ] && return 0
    done
    return 1
}

find_wifi_iface && exit 0

for usb_dev in /sys/bus/usb/devices/*; do
    [ -f "$usb_dev/idVendor" ] || continue
    [ -f "$usb_dev/idProduct" ] || continue
    [ "$(cat "$usb_dev/idVendor")" = "0bda" ] || continue
    [ "$(cat "$usb_dev/idProduct")" = "b720" ] || continue

    for intf in "$usb_dev":*; do
        [ -e "$intf" ] || continue
        [ -e "$intf/driver" ] && continue
        echo "${intf##*/}" > /sys/bus/usb/drivers_probe
    done
done

for _ in $(seq 1 10); do
    find_wifi_iface && exit 0
    sleep 1
done

echo "wifi-hw-init: RTL8723BU did not create a wireless interface" >&2
exit 1
