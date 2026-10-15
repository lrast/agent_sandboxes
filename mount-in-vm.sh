#!/bin/bash
# Share a host folder into the running VM at the same absolute path.
#
#   mount-in-vm [DIR]          # default .
#   mount-in-vm --list
#   mount-in-vm --unmount DIR
#
# Reverse sshfs: the host runs sftp-server, locked to DIR by sftp-share.sb, and the
# guest mounts it with `sshfs -o passive` over the existing ssh connection
# (vm_admin@localhost:2222). The VM never connects to the host.
# Mounts don't survive a VM restart (snapshot=on); the pipeline exits with the VM.
set -euo pipefail

REPO="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
RUN="$REPO/disks/run"
SSH=(ssh -F /dev/null -T
  -i "$REPO/keys/adminkey" -o IdentitiesOnly=yes
  -o UserKnownHostsFile="$REPO/keys/known_hosts" -o StrictHostKeyChecking=yes
  -o BatchMode=yes -o ConnectTimeout=5
  -o ServerAliveInterval=15 -o ServerAliveCountMax=4
  -p 2222 vm_admin@localhost)

die() { echo "mount-in-vm: $*" >&2; exit 1; }

# disks/run/<key>.{pid,dir,log,fifo}
key_for() { printf %s "$1" | shasum | cut -c1-16; }

# True if the pid file names a live pipeline of ours (guards against pid reuse)
alive() {
  local pid
  pid=$(cat "$RUN/$1.pid" 2>/dev/null) || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q -- '--_pipeline'
}

cleanup_key() { rm -f "$RUN/$1".{pid,dir,fifo}; }

# The guest end, run by vm_admin over ssh. DIR has no single quotes (checked).
remote_mount() {
  local d="$1"
  # Clear a dead mount left by a killed pipeline, then mount in the foreground so
  # the ssh session (and so the pipeline) lives exactly as long as the mount.
  # umount, not fusermount3: Ubuntu's AppArmor profile denies fusermount3 here.
  echo "sudo umount -l '$d' 2>/dev/null; sudo mkdir -p '$d' &&" \
    "exec sudo sshfs -f -o passive,allow_other,uid=\$(id -u bot),gid=\$(id -g bot)" \
    ":'$d' '$d'"
}

# Hidden mode: the background pipeline itself (started by `mount-in-vm DIR`).
pipeline() {
  local dir="$1" key="$2"
  local fifo="$RUN/$key.fifo"
  rm -f "$fifo"; mkfifo -m 600 "$fifo"
  # sftp-server <- fifo <- ssh <- sftp-server
  sandbox-exec -f "$REPO/sftp-share.sb" -D SHARE="$dir" \
      /usr/libexec/sftp-server -d "$dir" < "$fifo" |
    "${SSH[@]}" "$(remote_mount "$dir")" > "$fifo" || true
  cleanup_key "$key"
  echo "$(date '+%F %T') pipeline for $dir exited"
}

list() {
  local f key
  for f in "$RUN"/*.pid; do
    [ -e "$f" ] || continue
    key=$(basename "$f" .pid)
    if alive "$key"; then cat "$RUN/$key.dir"; else cleanup_key "$key"; fi
  done
}

unmount() {
  local dir key pid
  dir=$(realpath "$1" 2>/dev/null || printf %s "$1")
  key=$(key_for "$dir")
  [[ "$dir" != *"'"* ]] || die "unsupported path: $dir"
  "${SSH[@]}" "sudo umount '$dir' && sudo rmdir '$dir' 2>/dev/null; true" ||
    echo "mount-in-vm: could not unmount in the VM (not running?); stopping the host side" >&2
  if alive "$key"; then
    pid=$(cat "$RUN/$key.pid")
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  fi
  cleanup_key "$key"
  echo "unmounted $dir"
}

mount_dir() {
  local dir key i
  dir=$(realpath "${1:-.}") || die "no such directory: ${1:-.}"
  [ -d "$dir" ] || die "not a directory: $dir"

  # Never share $HOME, /, anything containing $HOME, or anything containing or
  # inside this repo (keys/ holds the VM's ssh keys and Claude token).
  local home repo
  home=$(realpath "$HOME"); repo=$(realpath "$REPO")
  [ "$dir" != / ] || die "refusing to share /"
  [ "$dir" != "$home" ] || die "refusing to share \$HOME"
  case "$home/" in "$dir/"*) die "refusing to share a parent of \$HOME: $dir" ;; esac
  case "$repo/" in "$dir/"*) die "refusing to share a folder containing $repo" ;; esac
  case "$dir/" in "$repo/"*) die "refusing to share a folder inside $repo" ;; esac
  case "$dir" in *"'"*|*$'\n'*) die "unsupported characters in path: $dir" ;; esac

  mkdir -p "$RUN"
  key=$(key_for "$dir")
  if alive "$key"; then echo "already mounted: $dir"; return; fi
  cleanup_key "$key"

  "${SSH[@]}" true 2>/dev/null || die "can't ssh to the VM (is it running? start_vm.sh)"

  printf '%s\n' "$dir" > "$RUN/$key.dir"
  nohup "$REPO/mount-in-vm" --_pipeline "$dir" "$key" < /dev/null >> "$RUN/$key.log" 2>&1 &
  echo $! > "$RUN/$key.pid"

  # Wait for the guest side to come up
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    alive "$key" || die "mount failed; see $RUN/$key.log"
    if "${SSH[@]}" "mountpoint -q '$dir'" 2>/dev/null; then
      echo "mounted $dir"; return
    fi
  done
  die "mount did not appear after 10s; see $RUN/$key.log (mount-in-vm --unmount $dir to stop)"
}

case "${1:-}" in
  --_pipeline) pipeline "$2" "$3" ;;
  --list) list ;;
  --unmount) [ $# -eq 2 ] || die "usage: mount-in-vm --unmount DIR"; unmount "$2" ;;
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' ;;
  -*) die "unknown option: $1 (see --help)" ;;
  *) [ $# -le 1 ] || die "usage: mount-in-vm [DIR]"; mount_dir "${1:-.}" ;;
esac
