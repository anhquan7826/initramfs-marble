#!/bin/busybox ash
# Optional USB RNDIS + telnet debug shell, enabled with marble.debug=y.
case " $(cat /proc/cmdline) " in
  *" marble.debug=y"*) ;;
  *) exit 0 ;;
esac

echo "[marble-init] starting USB RNDIS debug shell" > /dev/console 2>/dev/null

mkdir -p /sys/kernel/config
mount -t configfs configfs /sys/kernel/config 2>/dev/null || true

G=/sys/kernel/config/usb_gadget/g1
UDC=$(ls /sys/class/udc 2>/dev/null | head -n 1)
if [ -z "$UDC" ]; then
  echo "[marble-init] no UDC found" > /dev/console 2>/dev/null
  exit 0
fi

mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409"
echo 0x18d1 > "$G/idVendor" 2>/dev/null || true
echo 0xd001 > "$G/idProduct" 2>/dev/null || true
echo Xiaomi > "$G/strings/0x409/manufacturer" 2>/dev/null || true
echo marble-debug > "$G/strings/0x409/serialnumber" 2>/dev/null || true
echo "marble debug" > "$G/strings/0x409/product" 2>/dev/null || true
echo "USB debug" > "$G/configs/c.1/strings/0x409/configuration" 2>/dev/null || true

FN=rndis.usb0
mkdir -p "$G/functions/$FN" 2>/dev/null || true
if [ ! -d "$G/functions/$FN" ]; then
  FN=ncm.usb0
  mkdir -p "$G/functions/$FN" 2>/dev/null || true
fi
ln -sfn "$G/functions/$FN" "$G/configs/c.1/$FN" 2>/dev/null || true

if [ -z "$(cat "$G/UDC" 2>/dev/null)" ]; then
  echo "$UDC" > "$G/UDC" 2>/dev/null || true
fi

IFNAME=
i=0
while [ "$i" -lt 30 ]; do
  IFNAME=$(cat "$G/functions/$FN/ifname" 2>/dev/null) || IFNAME=
  [ -n "$IFNAME" ] && break
  sleep 1
  i=$((i + 1))
done
[ -n "$IFNAME" ] || IFNAME=rndis0

ifconfig "$IFNAME" 172.16.42.1 netmask 255.255.255.0 up 2>/dev/null || \
  ifconfig "$IFNAME" 172.16.42.1 2>/dev/null || true

killall telnetd 2>/dev/null || true
telnetd -p 23 -l /bin/sh 2>/dev/null || telnetd 2>/dev/null || true

echo "[marble-init] telnet 172.16.42.1 ($IFNAME)" > /dev/console 2>/dev/null
