#!/bin/sh
set -eu

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KDIR=${KDIR:-$SRC/../linux-7.2.8}
KCONFIG=${KCONFIG:-$SRC/../marble-poco-f5.config}
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
OUT=${OUT:-$SRC/initramfs}
JOBS=${JOBS:-$(nproc)}
COMPRESS=${COMPRESS:-zstd}
INCLUDE_MODULES=${INCLUDE_MODULES:-yes}
ROOTFS=${ROOTFS:-}
STAGE=$SRC/.build/rootfs

usage() {
  echo "KDIR=<kernel source> KCONFIG=<config> CROSS_COMPILE=<prefix> JOBS=<n> OUT=<file> COMPRESS=zstd|gzip INCLUDE_MODULES=yes|no ROOTFS=<rootfs dir> $0"
}

case "$COMPRESS" in
  zstd) compressor="zstd -q -c" ;;
  gzip) compressor="gzip -9c" ;;
  *) usage >&2; exit 1 ;;
esac

rm -rf "$STAGE"
mkdir -p "$STAGE/usr/bin" "$STAGE/usr/lib" "$STAGE/hooks" "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/run" "$STAGE/sysroot" "$STAGE/tmp" "$STAGE/etc" "$STAGE/boot"
ln -s usr/bin "$STAGE/bin"
ln -s usr/bin "$STAGE/sbin"
ln -s usr/lib "$STAGE/lib"
ln -s bin "$STAGE/usr/sbin"

install -m 755 "$SRC/busybox" "$STAGE/usr/bin/busybox"
for applet in sh ash mount umount blkid sleep mkdir cat modprobe switch_root ln dmesg sync halt reboot poweroff; do
  ln -sf busybox "$STAGE/usr/bin/$applet"
done
install -m 755 "$SRC/init" "$STAGE/init"
cp "$SRC/modules.list" "$STAGE/modules.list"
for hook in "$SRC"/hooks/*; do
  [ -f "$hook" ] || continue
  install -m 755 "$hook" "$STAGE/hooks/$(basename "$hook")"
done

if [ "$INCLUDE_MODULES" = yes ]; then
  if [ ! -f "$KDIR/.config" ] && [ -f "$KCONFIG" ]; then
    cp "$KCONFIG" "$KDIR/.config"
  fi
  make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" modules
  make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install
  if [ -n "$ROOTFS" ]; then
    make -C "$KDIR" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$ROOTFS" INSTALL_MOD_STRIP=1 modules_install
  fi
  moddir=$(find "$STAGE/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  find "$moddir" -type f -name '*.ko.zst' -exec sh -c '
    for f do
      zstd -q -d -f "$f" -o "${f%.zst}"
      rm -f "$f"
    done
  ' sh {} +
  for f in "$moddir"/modules.dep "$moddir"/modules.alias "$moddir"/modules.builtin; do
    [ -f "$f" ] || continue
    sed -i 's/\.ko\.zst/.ko/g' "$f"
  done
fi

(cd "$STAGE" && find . -print0 | cpio -0 -o -H newc -R 0:0 --quiet) | $compressor > "$OUT"
echo "wrote $OUT ($(stat -c %s "$OUT") bytes)"
