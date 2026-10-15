#!/bin/bash
set -e

# 1. Agent installer arguments
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"

if [ "$#" -ne 0 ]; then
  echo "Usage: $0   (Claude Code is always installed)" >&2
  exit 1
fi

echo "==> Agent to install: claude"

# 1. Prepare cloud-init directory
# cidata/ and the seed ISO contain the VM's private host key: remove them however
# this script exits (including a failed install).
trap 'rm -rf cidata disks/seed.iso' EXIT
echo "==> Creating cloud-init autoinstall configurations..."
(umask 077; mkdir -p cidata)
cat << 'EOF' > cidata/meta-data
instance-id: ubuntu-vm
local-hostname: ubuntu-vm
EOF

# SSH public keys to authorize (override via environment variables)
ADMIN_KEY_FILE="${ADMIN_KEY_FILE:-keys/adminkey.pub}"
BOT_KEY_FILE="${BOT_KEY_FILE:-keys/vmkey.pub}"

ADMIN_KEY=$(head -n 1 "$ADMIN_KEY_FILE")
BOT_KEY=$(head -n 1 "$BOT_KEY_FILE")
# The VM's sshd host key pair; pin the .pub on the host (StrictHostKeyChecking).
VM_HOST_KEY_FILE="${VM_HOST_KEY_FILE:-keys/vmhostkey}"
VM_HOST_PUBKEY=$(head -n 1 "$VM_HOST_KEY_FILE.pub")
grep -q "BEGIN OPENSSH PRIVATE KEY" "$VM_HOST_KEY_FILE" || {
  echo "ERROR: $VM_HOST_KEY_FILE is not an unencrypted OpenSSH private key" >&2; exit 1; }

# The user-data (#cloud-config) lives in vm-config.yaml; inject the keys
sed -e "s|__ADMIN_SSH_KEY__|${ADMIN_KEY}|" \
    -e "s|__BOT_SSH_KEY__|${BOT_KEY}|" \
    -e "s|__VM_HOST_PUBKEY__|${VM_HOST_PUBKEY}|" \
    -e "s#__AGENT_INSTALL_URL__#${CLAUDE_INSTALL_URL}#" \
    vm-config.yaml |
  # The private host key is multi-line: indent it into the "ed25519_private: |" block.
  awk -v keyfile="$VM_HOST_KEY_FILE" '
    $0 == "__VM_HOST_PRIVKEY__" { while ((getline l < keyfile) > 0) print "        " l; next }
    { print }' > cidata/user-data
chmod 600 cidata/user-data

# 3. Package the configuration into an ISO (using macOS native hdiutil)
echo "==> Creating seed.iso..."
rm -f disks/seed.iso
hdiutil makehybrid -iso -joliet -default-volume-name cidata -o disks/seed.iso cidata/ > /dev/null
chmod 600 disks/seed.iso

# 4. Create the disks (if they don't already exist)
echo "==> Preparing disks..."
mkdir -p disks

[ -f disks/os_base.qcow2 ] || qemu-img create -f qcow2 disks/os_base.qcow2 12G

# 5. Run the installer headlessly
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
  -cdrom ubuntu-26.04.1-live-server-arm64.iso \
  -drive file=disks/seed.iso,format=raw,if=virtio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -no-reboot

echo "==> Installation complete! You can now run your sandbox-exec command."
