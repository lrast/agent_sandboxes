#!/bin/bash
# Runs once as root on the installed system's very first boot (cloud-init runcmd).
# Inlined into user-data write_files by install_os.sh (see vm-config.yaml).
# No set -e: a failing step shouldn't skip the rest (e.g. the ssh reload).

systemctl enable --now nftables.service
systemctl try-reload-or-restart ssh.service

# rtk instructions/hook for the bot's Claude Code. Run as bot so it configures
# /home/bot/.claude; full path because runcmd isn't a PAM session (no /etc/environment).
# --auto-patch: without a tty, its "Patch settings.json?" prompt defaults to N and
# the PreToolUse hook is never installed.
runuser -u bot -- env HOME=/home/bot /opt/agent/.local/bin/rtk init --global --auto-patch
