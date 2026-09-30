# Commands that I'm running

## Create disks
qemu-img create -f qcow2 os_base.qcow2 12G
qemu-img create -f qcow2 state_disk.qcow2 10G



## Setup

### Install OS (iso downloaded from ubuntu.com)

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
  -cdrom ubuntu-26.04.1-live-server-arm64.iso

### Mounting modifiable disk

#### Format it (First boot ONLY)
sudo mkfs.ext4 /dev/vdb

##### Create your specific mount location
mkdir -p /home/bot/state

##### Mount it
sudo mount /dev/vdb /home/bot/state

echo '/dev/vdb /home/bot/state ext4 defaults 0 2' | sudo tee -a /etc/fstab
sudo chown -R bot:bot /home/bot/state



## Run

### Start up 

sandbox-exec -f qemu-sandbox.sb qemu-system-aarch64 \
  -accel hvf \
  -cpu host \
  -m 4G \
  -smp 4 \
  -M virt \
  -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive file=os_base.qcow2,if=virtio,snapshot=on\
  -drive file=state_disk.qcow2,if=virtio\
  -netdev user,id=net0,restrict=on,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:8181-:8181 \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -daemonize


