#!/bin/bash
# Fail fast: never start the VM if setup steps (TMPDIR, cleanup) failed.
set -euo pipefail

# qemu puts the snapshot=on overlay in $TMPDIR; keep it inside the sandbox-allowed disks/tmp
export TMPDIR="$(pwd)/disks/tmp"
mkdir -p "$TMPDIR"

# Precaution: remove stale qemu temp files (snapshot overlays vl.* and guest-RAM
# backing files memfd-*) left by a crashed/killed previous run, so old guest disk
# and memory contents don't linger on the host. Skipped if a VM is already running,
# so a live VM's files are never deleted.
if ! pgrep -qf qemu-system-aarch64; then
  rm -f "$TMPDIR"/vl.* "$TMPDIR"/memfd-*
fi

# Guest has internet access (restrict=off); qemu-sandbox.sb denies connections to
# this Mac, and the guest's nftables firewall denies the LAN.
exec sandbox-exec -f qemu-sandbox.sb qemu-system-aarch64 \
  -nodefaults -no-user-config \
  -accel hvf \
  -cpu host \
  -m 4G \
  -smp 4 \
  -M virt \
  -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive file=disks/os_base.qcow2,format=qcow2,if=virtio,snapshot=on \
  -netdev user,id=net0,restrict=off,ipv6=off,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display none -monitor none -serial none\
  -daemonize
