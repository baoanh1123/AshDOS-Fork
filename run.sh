#!/usr/bin/env bash
if [ ! -f disk.img ]; then
    echo "Please run ./build.sh first"
    exit 1
fi
case $1 in
  "serial-kvm")
    qemu-system-x86_64 -hda disk.img -net nic -net user -enable-kvm -m 512M -nographic
    ;;
  "kvm")
    qemu-system-x86_64 -hda disk.img -net nic -net user -enable-kvm -m 512M
    ;;
  "serial-nonkvm")
    qemu-system-x86_64 -hda disk.img -net nic -net user -nographic -m 512M
    ;;
  "nonkvm")
    qemu-system-x86_64 -hda disk.img -net nic -net user -m 512M
    ;;
  *)
    echo "Usage: $0 [option]"
    echo "Example:"
    echo "- $0 kvm        : run qemu interface and use kvm for optimization"
    echo "- $0 serial-kvm : to run qemu with no interface and control via serial console, use kvm for optimization"
    echo "Options: serial-kvm kvm serial-nonkvm nonkvm"
    ;;
esac