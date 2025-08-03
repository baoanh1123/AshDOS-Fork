#!/usr/bin/env bash
set -e

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Please run this script with sudo or as the root user."
        exit 1
    fi
}

install_packages() {
    local pkgs=("$@")
    local pkg_manager=""
    
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
    elif command -v pacman &> /dev/null; then
        pkg_manager="pacman"
    else
        echo "Error: No supported package manager found. Please install packages manually."
        exit 1
    fi

    echo "Detected package manager: $pkg_manager. Installing packages..."
    
    case "$pkg_manager" in
        "apt-get")
            apt-get update
            apt-get install -y "${pkgs[@]}"
            ;;
        "dnf"|"yum")
            $pkg_manager install -y "${pkgs[@]}"
            ;;
        "pacman")
            pacman -Syu --noconfirm
            pacman -S --noconfirm "${pkgs[@]}"
            ;;
    esac
}

check_root

declare -A packages
declare -A groups

packages["debian"]="build-essential gcc g++ make libncurses-dev bison flex libssl-dev libelf-dev bc autoconf automake libtool git qemu-system-x86 cpio gzip"
packages["ubuntu"]="${packages["debian"]}"
packages["fedora"]="ncurses-devel openssl-devel elfutils-libelf-devel bc autoconf automake libtool git qemu-system-x86 cpio gzip"
packages["centos"]="${packages["fedora"]}"
packages["rhel"]="${packages["fedora"]}"
packages["arch"]="base-devel ncurses openssl libelf bc autoconf automake libtool git qemu-system-x86 cpio gzip"

groups["fedora"]="Development Tools"
groups["centos"]="${groups["fedora"]}"
groups["rhel"]="${groups["fedora"]}"

distro_id=""
if [ -f "/etc/os-release" ]; then
    . /etc/os-release
    ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    ID_LIKE=$(echo "$ID_LIKE" | tr '[:upper:]' '[:lower:]')
    
    if [ -n "${packages[$ID]}" ]; then
        distro_id=$ID
    elif [ -n "$ID_LIKE" ]; then
        for d in $ID_LIKE; do
            if [ -n "${packages[$d]}" ]; then
                distro_id=$d
                break
            fi
        done
    fi
else
    echo "Error: Could not determine distribution. Please install packages manually."
    exit 1
fi

if [ -n "$distro_id" ]; then
    echo "Distribution detected: $distro_id"
    
    if [[ -n "${groups[$distro_id]}" ]]; then
        group_manager=""
        if command -v dnf &> /dev/null; then
            group_manager="dnf"
        elif command -v yum &> /dev/null; then
            group_manager="yum"
        fi

        if [ -n "$group_manager" ]; then
            echo "Installing package groups..."
            $group_manager groupinstall -y "${groups[$distro_id]}"
        fi
    fi

    IFS=' ' read -r -a pkgs_arr <<< "${packages[$distro_id]}"
    install_packages "${pkgs_arr[@]}"
else
    echo "Distribution '$ID' is not supported by this script. Please install packages manually."
    exit 1
fi

echo "All required packages have been installed successfully."
