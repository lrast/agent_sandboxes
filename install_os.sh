#!/bin/bash
set -e

# package URLs live at the top of vm-scripts/late-commands.sh)
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
# Pin it for host-side ssh (mount-in-vm, Zed agent): StrictHostKeyChecking=yes
printf '[localhost]:2222 %s\n' "$(cut -d' ' -f1,2 "$VM_HOST_KEY_FILE.pub")" > keys/known_hosts

# Long-lived Claude Code OAuth token (claude setup-token, ~1 year), baked into the
# image so the bot is logged in on every boot. A normal /login would not survive:
# its refresh token rotates, and snapshot=on discards the rotated one.
# Cached in keys/; delete the file to log in again.
CLAUDE_TOKEN_FILE="${CLAUDE_TOKEN_FILE:-keys/claude_oauth_token}"
if [ ! -s "$CLAUDE_TOKEN_FILE" ]; then
  echo "==> Logging in to Claude Code (claude setup-token)..."
  claude setup-token
  read -rsp "Paste the token printed above: " CLAUDE_TOKEN; echo
  (umask 077; printf '%s\n' "$CLAUDE_TOKEN" > "$CLAUDE_TOKEN_FILE")
fi
CLAUDE_TOKEN=$(head -n 1 "$CLAUDE_TOKEN_FILE")
# Format check; also keeps the sed substitution below safe.
[[ "$CLAUDE_TOKEN" =~ ^sk-ant-oat[0-9]+-[A-Za-z0-9_-]+$ ]] || {
  echo "ERROR: $CLAUDE_TOKEN_FILE does not contain a valid Claude OAuth token" >&2; exit 1; }

# Multi-line files inlined into user-data by the awk step below
LATE_COMMANDS_FILE=vm-scripts/late-commands.sh
FIRST_BOOT_FILE=vm-scripts/first-boot.sh
for f in "$LATE_COMMANDS_FILE" "$FIRST_BOOT_FILE"; do
  [ -r "$f" ] || { echo "ERROR: cannot read $f" >&2; exit 1; }
done

# The user-data (#cloud-config) lives in vm-config.yaml; inject the keys
sed -e "s|__ADMIN_SSH_KEY__|${ADMIN_KEY}|" \
    -e "s|__CLAUDE_OAUTH_TOKEN__|${CLAUDE_TOKEN}|" \
    -e "s|__BOT_SSH_KEY__|${BOT_KEY}|" \
    -e "s|__VM_HOST_PUBKEY__|${VM_HOST_PUBKEY}|" \
    vm-config.yaml |
  # Multi-line values: a line holding only a placeholder is replaced by the file,
  # each line given the placeholder's indent, so it lands inside its YAML "|" block.
  awk -v keyfile="$VM_HOST_KEY_FILE" \
      -v late="$LATE_COMMANDS_FILE" \
      -v boot="$FIRST_BOOT_FILE" '
    function inline(file,   indent, l) {
      indent = $0; sub(/[^ ].*/, "", indent)
      while ((getline l < file) > 0) print (l == "" ? "" : indent l)
      close(file)
    }
    NF == 1 && $1 == "__VM_HOST_PRIVKEY__"  { inline(keyfile); next }
    NF == 1 && $1 == "__LATE_COMMANDS_SH__" { inline(late);    next }
    NF == 1 && $1 == "__FIRST_BOOT_SH__"    { inline(boot);    next }
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
