# Setup for agent sandboxed

This is the master copy. Setup should follow from this version to avoid corrupt instructions leading to insecure setups.

## This is a looser sandboxing for less experimental agents

Security posture: prevent data exfiltration, but don't be overly restrictive on web access.
Intended for use by coding agents


## Workflow - target:

Periodically:
1. Create clean OS disk, keys
2. copy disk, sandbox, start-up commands to /Users/Shared and sync across accounts there.

## Workflow - daily use

1. Start the VM: `./start_vm.sh`
2. In each project: `cd projA && mount-in-vm . && zed .`
3. In Zed's agent panel, pick the "Claude (VM)" agent.

`mount-in-vm` (symlink it into PATH: `ln -s "$PWD/mount-in-vm" ~/.local/bin/`) shares one folder into the running VM at the same absolute path, and nothing else (not even the folder's parent).
`mount-in-vm --list` shows live shares, `mount-in-vm --unmount DIR` removes one. Shares are gone after a VM restart; mount again.
It refuses `/`, `$HOME` and its parents, and anything containing or inside this repo (`keys/`).

How it works: reverse sshfs. For each folder the host runs `/usr/libexec/sftp-server`, locked to that folder by `sftp-share.sb`, and pipes it through `ssh vm_admin@localhost:2222` to `sshfs -o passive` in the guest. The VM never opens a connection to the host; no extra ports, no qemu restart.
Files appear in the VM owned by `bot`; files the agent writes are owned by you on the host.
To stop the agent planting code that runs on the host, `sftp-share.sb` denies writes to `.git` itself, `.git/hooks`, `.git/config`, `.git/modules` and `.zed/`. So in the VM, `git init`, `git config` and commits in submodules fail; do those on the host. Normal commits work.
Logs: `disks/run/*.log`. Sandbox denials: `log show --last 5m --predicate 'sender=="Sandbox"'`.

The Zed agent is a custom `agent_servers` entry in `~/.config/zed/settings.json`: `ssh -i keys/vmkey … bot@localhost /opt/agent/acp/bin/claude-agent-acp`, with `keys/known_hosts` pinning the VM host key (written by `install_os.sh`).

## Install

Guest-side setup scripts live in `vm-scripts/`: `late-commands.sh` (install time, in the installer) and `first-boot.sh` (first boot, as root). `install_os.sh` inlines them into the cloud-init user-data built from `vm-config.yaml` (`__LATE_COMMANDS_SH__`, `__FIRST_BOOT_SH__` placeholders).

### Claude Code login

`install_os.sh` bakes a long-lived Claude Code token into the image, so the bot is logged in on every boot.
On first install it runs `claude setup-token` (browser login) and asks you to paste the token; it is cached in `keys/claude_oauth_token`.
Delete that file to log in again (e.g. when the token expires after ~1 year).
The token is in plain text in `disks/os_base.qcow2`: anyone who can read the disk image can use the account.

## Improvements:

Crank down permissions for the network access (e.g. local servers) and sftp server
