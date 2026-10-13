#!/bin/bash
set -e

# 1. Agent installer arguments
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
HERMES_INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"

usage() {
  echo "Usage: $0 [--claude | --hermes]   (no flag = no agent installed)" >&2
  exit 1
}

AGENT=""
for arg in "$@"; do
  case "$arg" in
    --claude) [ -z "$AGENT" ] || usage; AGENT=claude ;;
    --hermes) [ -z "$AGENT" ] || usage; AGENT=hermes ;;
    *) usage ;;
  esac
done

AGENT_INSTALL_URL=""
case "$AGENT" in
  claude) AGENT_INSTALL_URL="$CLAUDE_INSTALL_URL" ;;
  hermes) AGENT_INSTALL_URL="$HERMES_INSTALL_URL" ;;
esac
if [ -n "$AGENT" ]; then
  if [ -z "$AGENT_INSTALL_URL" ]; then
    echo "ERROR: install URL for '$AGENT' is not set at the top of $0" >&2
    exit 1
  fi
  echo "==> Agent to install: $AGENT"
else
  echo "==> No agent selected (pass --claude or --hermes to install one)"
fi

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
# Lines marked "#@agent#" are kept (marker stripped) only if an agent was chosen.
if [ -n "$AGENT" ]; then
  AGENT_SED='s/^#@agent#//'
else
  AGENT_SED='/^#@agent#/d'
fi

sed -e "$AGENT_SED" \
    -e "s|__ADMIN_SSH_KEY__|${ADMIN_KEY}|" \
    -e "s|__BOT_SSH_KEY__|${BOT_KEY}|" \
    -e "s#__AGENT_INSTALL_URL__#${AGENT_INSTALL_URL}#" \
    vm-config.yaml > cidata/user-data

# 3. Package the configuration into an ISO (using macOS native hdiutil)
echo "==> Creating seed.iso..."
rm -f disks/seed.iso
hdiutil makehybrid -iso -joliet -default-volume-name cidata -o disks/seed.iso cidata/ > /dev/null

# 4. Create the disks (if they don't already exist)
echo "==> Preparing disks..."
mkdir -p disks

[ -f disks/os_base.qcow2 ] || qemu-img create -f qcow2 disks/os_base.qcow2 12G
[ -f disks/state_disk.qcow2 ] || qemu-img create -f qcow2 disks/state_disk.qcow2 10G

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
