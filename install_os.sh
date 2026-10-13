#!/bin/bash
set -e

# 1. Prepare cloud-init directory
echo "==> Creating cloud-init autoinstall configurations..."
mkdir -p cidata
cat << 'EOF' > cidata/meta-data
instance-id: ubuntu-vm
local-hostname: ubuntu-vm
EOF

# SSH public keys to authorize (override via environment variables)
ADMIN_KEY_FILE="${ADMIN_KEY_FILE:-keys/adminkey.pub}"
BOT_KEY_FILE="${BOT_KEY_FILE:-keys/vmkey.pub}"

ADMIN_KEY=$(head -n 1 "$ADMIN_KEY_FILE")
BOT_KEY=$(head -n 1 "$BOT_KEY_FILE")

# The user-data (#cloud-config) lives in vm-config.yaml; inject the keys
sed -e "s|__ADMIN_SSH_KEY__|${ADMIN_KEY}|" \
    -e "s|__BOT_SSH_KEY__|${BOT_KEY}|" \
    vm-config.yaml > cidata/user-data

# 2. Package the configuration into an ISO (using macOS native hdiutil)
echo "==> Creating seed.iso..."
rm -f disks/seed.iso
hdiutil makehybrid -iso -joliet -default-volume-name cidata -o disks/seed.iso cidata/ > /dev/null

# 3. Create the disks (if they don't already exist)
echo "==> Preparing disks..."
mkdir -p disks

[ -f disks/os_base.qcow2 ] || qemu-img create -f qcow2 disks/os_base.qcow2 12G
[ -f disks/state_disk.qcow2 ] || qemu-img create -f qcow2 disks/state_disk.qcow2 10G

# 4. Run the installer headlessly
echo "==> Starting (almost headless) installation..."
echo "    This usually takes 5 to 10 minutes."
echo "    QEMU will automatically exit when the installation is finished."

qemu-system-aarch64 \
  -accel hvf \
  -cpu host \
  -m 4G \
  -smp 4 \
  -M virt \
  -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -device virtio-gpu-pci \
  -display default,show-cursor=on \
  -device qemu-xhci \
  -device usb-kbd \
  -device usb-tablet \
  -drive file=disks/os_base.qcow2,format=qcow2,if=virtio \
  -drive file=disks/state_disk.qcow2,format=qcow2,if=virtio \
  -cdrom ubuntu-26.04.1-live-server-arm64.iso \
  -drive file=disks/seed.iso,format=raw,if=virtio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -no-reboot

echo "==> Cleanup."
rm -r cidata
rm disks/seed.iso
echo "==> Installation complete! You can now run your sandbox-exec command."
