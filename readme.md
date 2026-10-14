# Setup for agent sandboxed

This is the master copy. Setup should follow from this version to avoid corrupt instructions leading to insecure setups.

## This is a looser sandboxing for less experimental agents

Security posture: prevent data exfiltration, but don't be overly restrictive on web access


## Workflow - target:

Periodically:
1. Create clean OS disk, keys
2. copy disk, sandbox, start-up commands to /Users/Shared and sync across accounts there.
