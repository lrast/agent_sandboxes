#!/bin/bash
set -e

# 1. Prepare cloud-init directory
echo "==> Creating cloud-init autoinstall configurations..."
mkdir -p cidata
cat << 'EOF' > cidata/meta-data
instance-id: ubuntu-vm
local-hostname: ubuntu-vm
EOF

# Generate a SHA-512 password hash for the user "bot"
# (Default password will be "bot")
PASS_HASH=$(openssl passwd -6 bot)

# Create the user-data configuration
cat << EOF > cidata/user-data
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ubuntu-vm
    username: bot
    password: "${PASS_HASH}"
  ssh:
    install-server: true
    allow-pw: true
  # This block gets passed to the final OS and runs on its VERY FIRST boot
  user-data:
    runcmd:
      # Check if /dev/vdb is already formatted; if not, format it
      - blkid /dev/vdb || mkfs.ext4 /dev/vdb
      - mkdir -p /home/bot/state
      - echo '/dev/vdb /home/bot/state ext4 defaults 0 2' >> /etc/fstab
      - mount -a
      - chown -R bot:bot /home/bot/state
      
EOF

# remove noexec if the agent needs to run things off the state disk



# 2. Package the configuration into an ISO (using macOS native hdiutil)
echo "==> Creating seed.iso..."
hdiutil makehybrid -iso -joliet -default-volume-name cidata -o seed.iso cidata/ > /dev/null

# 3. Create the disks (if they don't already exist)
echo "==> Preparing disks..."
[ -f os_base.qcow2 ] || qemu-img create -f qcow2 os_base.qcow2 12G
[ -f state_disk.qcow2 ] || qemu-img create -f qcow2 state_disk.qcow2 10G

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
  -drive file=os_base.qcow2,format=qcow2,if=virtio \
  -drive file=state_disk.qcow2,format=qcow2,if=virtio \
  -cdrom ubuntu-26.04.1-live-server-arm64.iso \
  -drive file=seed.iso,format=raw,if=virtio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -no-reboot

echo "==> Cleanup."
rm -r cidata
rm seed.iso
echo "==> Installation complete! You can now run your sandbox-exec command."
