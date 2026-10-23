#!/bin/bash
# Runs once at install time in the installer environment; /target is the new system.
# Inlined into the autoinstall late-commands by install_os.sh (see vm-config.yaml).
# Needs network only during install.
set -euo pipefail

# Package sources
UV_INSTALL_URL="https://astral.sh/uv/install.sh"
CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
ACP_NPM_PACKAGE="@agentclientprotocol/claude-agent-acp"
RTK_INSTALL_URL="https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh"

# uv: downloaded by the installer's curl straight into the target's /usr/local/bin
curl -LsSf "$UV_INSTALL_URL" | env UV_INSTALL_DIR=/target/usr/local/bin UV_NO_MODIFY_PATH=1 sh

# Claude Code.
# Downloaded in the installer, then run inside the target chroot as root with
# HOME=/opt/agent so it lands in a system-wide location (the bot user doesn't
# exist yet; cloud-init creates it on first boot).
mkdir -p /target/opt/agent
curl -fsSL "$CLAUDE_INSTALL_URL" -o /target/tmp/agent-install.sh
curtin in-target --target=/target -- env HOME=/opt/agent bash -c 'umask 022 && bash /tmp/agent-install.sh'
rm -f /target/tmp/agent-install.sh
chmod -R a+rX /target/opt/agent

# Put claude (/opt/agent/bin) and rtk (/opt/agent/.local/bin) on PATH via
# /etc/environment: pam_env applies it to every ssh session, including Zed's
# non-interactive "ssh bot@... claude-agent-acp" (which skips profile.d).
# Not a shell file: no $PATH expansion, so prepend to the existing line.
AGENT_PATH="/opt/agent/.local/bin:/opt/agent/bin"
if grep -q '^PATH="' /target/etc/environment; then
  sed -i "s|^PATH=\"|PATH=\"$AGENT_PATH:|" /target/etc/environment
else
  echo "PATH=\"$AGENT_PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"" >> /target/etc/environment
fi

# ACP adapter for Zed's "Claude (VM)" agent (run over ssh as bot):
# /opt/agent/acp/bin/claude-agent-acp
curtin in-target --target=/target -- bash -c 'umask 022 && npm install -g --prefix /opt/agent/acp "$1"' _ "$ACP_NPM_PACKAGE"
chmod -R a+rX /target/opt/agent/acp

# rtk: installed straight into the target's /opt/agent/.local/bin (already on PATH
# via /etc/environment above)
mkdir -p /target/opt/agent/.local/bin
curl -fsSL "$RTK_INSTALL_URL" | RTK_INSTALL_DIR=/target/opt/agent/.local/bin sh
chmod -R a+rX /target/opt/agent/.local
