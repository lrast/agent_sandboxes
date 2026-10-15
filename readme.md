# Setup for agent sandboxed

This is the master copy. Setup should follow from this version to avoid corrupt instructions leading to insecure setups.

## This is a looser sandboxing for less experimental agents

Security posture: prevent data exfiltration, but don't be overly restrictive on web access


## Workflow - target:

Periodically:
1. Create clean OS disk, keys
2. copy disk, sandbox, start-up commands to /Users/Shared and sync across accounts there.

## Claude Code login

`install_os.sh` bakes a long-lived Claude Code token into the image, so the bot is logged in on every boot.
On first install it runs `claude setup-token` (browser login) and asks you to paste the token; it is cached in `keys/claude_oauth_token`.
Delete that file to log in again (e.g. when the token expires after ~1 year).
The token is in plain text in `disks/os_base.qcow2`: anyone who can read the disk image can use the account.
