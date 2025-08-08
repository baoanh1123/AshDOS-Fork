#!/usr/bin/env bash
set -e


if [ -f disk.img ]; then
    echo "Already built, please run ./run.sh"
    exit 1
fi
# checking root permission
if [[ $EUID -ne 0 ]]; then
    echo "please use sudo or run the script as root"
    exit 1
fi

current_working_directory=$(pwd)

# sudo apt update -y
# sudo apt install -y build-essential gcc g++ make libncurses-dev bison flex libssl-dev libelf-dev bc autoconf automake libtool git qemu-system-x86 cpio gzip

git clone https://github.com/torvalds/linux --depth 1
git clone https://github.com/bminor/glibc --depth 1
git clone https://github.com/mirror/busybox --depth 1
git clone https://github.com/mirror/ncurses.git --depth 1
git clone https://github.com/bminor/bash.git --depth 1
wget https://ftp.gnu.org/gnu/readline/readline-8.3.tar.gz -O libreadline.tar.gz

mkdir readline

tar -xzf libreadline.tar.gz --strip-components=1 -C readline
# Create disk.img
dd if=/dev/zero of=disk.img bs=1M count=512

# Find an available loop device
loop_device=$(losetup -fP --show disk.img)

# Create partition
sfdisk $loop_device << EOF
label: dos
device: /dev/$loop_device
unit: sectors

${loop_device}p1 : size=100M, type=83, bootable
${loop_device}p2 : type=83
EOF

# Reload partition table
partprobe "$loop_device"

# Format partition

mkfs.ext4 $loop_device"p2"
mkfs.vfat -F 32 $loop_device"p1"

# Create a mount directory
mkdir /mnt/ashdos

# Mounting partition to the mount point
mount ${loop_device}p2 /mnt/ashdos
mount ${loop_device}p1 --mkdir /mnt/ashdos/boot

# Create a directory for the root system
mkdir -p /mnt/ashdos/{proc,sys,etc,tmp,usr,usr/lib,usr/bin,dev,var,root,etc}
# Change directory and create needed symlinks
cd /mnt/ashdos
ln -s usr/lib lib
ln -s usr/lib lib64
ln -s usr/bin sbin
ln -s usr/bin bin
cd usr
ln -s bin sbin
ln -s lib lib64
cd $current_working_directory
# Step 1: Compile Linux Kernel
cd ./linux
    make defconfig
    make -j$(nproc) bzImage
cd ..

# Step 2: Compile glibc
cd glibc
    mkdir -p build
    cd build
        ../configure --prefix=/usr --disable-multilib 
        
        make -j$(nproc) 
        
        make DESTDIR=/mnt/ashdos/ install 
        
    cd ..
cd ..

# Step 3: Compile BusyBox with networking tools
echo "Compiling BusyBox..."
cd ./busybox
    make defconfig 
    
    sed -i 's/CONFIG_TC=y/CONFIG_TC=n/g' .config
    make -j$(nproc) 
    
cd ..

# Step 4: Compile Libreadline and Libncurses for bash working
echo "Compiling Libreadline and Libncurses"
cd ./ncurses
    CFLAGS='-std=gnu17' ./configure --with-shared --with-termlib --enable-widec --with-versioned-syms --prefix=/usr 
    
    make -j$(nproc) > /dev/null 2>&1 &
    
    make DESTDIR=/mnt/ashdos/ install > /dev/null 2>&1 &
    
cd ..
cd ./readline
    CFLAGS='-std=gnu17' ./configure --prefix=/usr 
    
    make -j$(nproc) 
    
    make DESTDIR=/mnt/ashdos/ install 
    
cd ..
# Step 5: Compile bash
cd bash
    ./configure --prefix=/usr 
    
    make -j$(nproc) 
    make DESTDIR=/mnt/ashdos/ install 
    
cd ..

# Create symlink for busybox applet
cp ./busybox/busybox /mnt/ashdos/bin/
cd /mnt/ashdos/bin
if [ -f clear ]; then
    rm clear
fi
for command in $(./busybox --list | grep -v '\[\|\[\['); do
    if [ ! -e "$command" ]; then
        ln -s busybox "$command"
    fi
done

cd $current_working_directory

# Create symlink for ncurses
ln -s libncursesw.so.6 /mnt/ashdos/usr/lib/libncurses.so.6
ln -s libformw.so.6 /mnt/ashdos/usr/lib/libform.so.6
ln -s libpanelw.so.6 /mnt/ashdos/usr/lib/libpanel.so.6
ln -s libmenuw.so.6 /mnt/ashdos/usr/lib/libmenu.so.6
ln -s libtinfow.so.6 /mnt/ashdos/usr/lib/libtinfo.so.6
# Create root user
echo "root::0:0:root:/root:/bin/bash" > /mnt/ashdos/etc/passwd

# Create udhcpc hook
cat << 'EOF' >> /mnt/ashdos/etc/udhcpc_hook.sh
#!/bin/sh

case "$1" in
    deconfig)
        [ -n "$interface" ] && ifconfig "$interface" 0.0.0.0 > /dev/null 2>&1
        route del default gw 0.0.0.0 dev "$interface" > /dev/null 2>&1
        ;;

    bound|renew)
        ifconfig "$interface" "$ip" netmask "$netmask" up > /dev/null 2>&1

        if [ -n "$router" ]; then
            route add default gw "$router" dev "$interface" > /dev/null 2>&1
        fi

        if [ -n "$dns" ]; then
            echo "nameserver $dns" > /etc/resolv.conf
        fi
        ;;
esac

exit 0
EOF
chmod +x /mnt/ashdos/etc/udhcpc_hook.sh

# Update ld.so.cache
echo "/usr/lib" > /mnt/ashdos/etc/ld.so.conf
ldconfig -v -r /mnt/ashdos/

# Create .bashrc file (optional)

cat << 'EOF' >> /mnt/ashdos/root/.bash_profile
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
cat << 'EOF' >> /mnt/ashdos/root/.bashrc
export PATH="/usr/bin:/usr/local/bin"
export PS1='┌──[\[\e[1;2m\]\h\[\e[0m\]]<\[\e[38;5;40m\]\w\[\e[0m\]>(\[\e[38;5;135;1m\]$?\[\e[0m\])\n└──\$ '
alias ls='ls --color=auto'
alias ll='ls -l'
alias l='ls -CF'
alias la='ls -A'
alias cls='clear'
EOF

# Create init script with networking setup
cat > /mnt/ashdos/init << 'EOF'
#!/bin/bash

# Set up initial configuration
mount -t proc proc /proc
mount -t sysfs sysfs /sys

# set up mdev                 
mdev -s
echo "/sbin/mdev" > /proc/sys/kernel/hotplug
mdev -d &
# Find network interface
INTERFACE=""
for I in $(ls /sys/class/net)               
do
    if [ "$I" != "lo" ]; then
        INTERFACE=$I
        break                
    fi
done                         
                    
# Start networking if interface is found
if [ -n "$INTERFACE" ]; then
    ifconfig "$INTERFACE" up
    udhcpc -i "$INTERFACE" -s /etc/udhcpc_hook.sh -x AshDOS &
fi                                                      
hostname AshDOS
export TERM=xterm-256color    
# Init messages                                    
clear
echo "Welcome to AshDOS!"
date
free -h | grep Mem
echo ""
echo "Type root to login!"
                         
# Start task
for TTY in 1 2 3 4 5 6 S0; do
    /sbin/getty -L 115200 tty$TTY vt100 &
done
# Keep init process running
while true; do
    sleep 10000000
done
EOF
chmod +x /mnt/ashdos/init

cat > /mnt/ashdos/etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
chmod 777 /mnt/ashdos/etc/resolv.conf

# Set up DPKG
mkdir -p /mnt/ashdos/var/lib/dpkg/info
cat > /mnt/ashdos/var/lib/dpkg/status << EOF
Package: libc6
Status: install ok installed
Architecture: amd64
Version: unknow

Package: bash
Status: install ok installed
Architecture: amd64
Version: unknow

Package: libncurses
Status: install ok installed
Architecture: amd64
Version: unknow

Package: libreadline
Status: install ok installed
Architecture: amd64
Version: unknow
EOF

# Copy kernel to disk
cp ./linux/arch/x86/boot/bzImage /mnt/ashdos/boot/vmlinuz

# Install Grub to disk
grub-install --target=i386-pc --boot-directory=/mnt/ashdos/boot --no-floppy $loop_device

# Create Grub config
cat << 'EOF' >> /mnt/ashdos/boot/grub/grub.cfg
menuentry 'ASHDOS' {
        set root='(hd0,1)'
        linux /vmlinuz root=/dev/sda2 rw loglevel=3 init=/init
}
menuentry 'ASHDOS SERIAL CONSOLE (ttyS0)' {
        set root='(hd0,1)'
        linux /vmlinuz root=/dev/sda2 rw console=ttyS0 loglevel=3 init=/init
}
EOF

# Clean up
cd $current_working_directory
umount /mnt/ashdos/boot /mnt/ashdos/
losetup -d $loop_device
chmod o+w disk.img
rm -rf bash busybox glibc ncurses readline libreadline.tar.gz linux
rm -rf /mnt/ashdos
clear
echo "Build successful, See Readme.md for how to run"
