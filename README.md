## This is a fork from the tutorial repository https://github.com/EHowardHill/AshDOS-Tutorial

I saw this script and it was interesting but the main weakness was that it was all in one initramfs file so the data would be lost on reboot, so I decided to rewrite it based on that script.

### What I have done:
- Create a virtual drive with 2 partitions boot and rootfs
- Install grub instead of booting qemu kernel parameters directly
- Install bash,libreadline,libncurses for more friendly instead of busybox ash
- I also changed a little bit instead of using devtmpfs I use mdev
- Now udhcpc is the main dhcp client that can help to connect network without static ip configuration

### How to build:
First run:
```bash
sudo ./setup.sh
```
After run:
```bash
sudo ./build.sh
```
### How to run:
run file to see more ./run.sh

For example:
```bash
./run.sh serial-kvm 
# Run with kvm optimization and communication over serial
```
