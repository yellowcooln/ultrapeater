#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    show_error "Installation requires root privileges.\n\nPlease run: sudo $0"
    exit 1
fi

sanitize_luckfox_cfg() {
    local cfg_path="/etc/luckfox.cfg"
    local sanitized_path

    if [ ! -f "$cfg_path" ]; then
        return 0
    fi

    # Some Luckfox Ubuntu images ship or rewrite this file with leading NUL bytes.
    # When that happens, `luckfox-config load` treats it as binary and silently skips
    # the saved SPI/UART settings, so `/dev/spidev*` never appears on boot.
    sanitized_path="$(mktemp)"
    tr -d '\000' <"$cfg_path" >"$sanitized_path"

    if ! cmp -s "$cfg_path" "$sanitized_path"; then
        install -m 0644 "$sanitized_path" "$cfg_path"
    fi

    rm -f "$sanitized_path"
}

echo "Setting localtime to UTC..."
rm /etc/localtime
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

echo "Setting hostname to ultrapeater..."
echo "ultrapeater" > /etc/hostname
echo "127.0.0.1 ultrapeater" >> /etc/hosts

echo "Sanitizing Luckfox config state"
sanitize_luckfox_cfg

echo "Disabling the UARTS we need for GPIO and enabling SPI"
luckfox-config uart_disable 4 1
luckfox-config uart_disable 2 1

echo "Enabling UART0 for shell and SPI"
luckfox-config spi_enable
sanitize_luckfox_cfg

DEBIAN_FRONTEND=noninteractive

echo "Update packages"
apt upgrade -y --option Dpkg::Options::="--force-confold"

echo "Installing packages"
apt install -y --option Dpkg::Options::="--force-confold" locales git libyaml-cpp-dev libbluetooth-dev openssl libssl-dev libulfius-dev fonts-noto-color-emoji ninja-build chrony software-properties-common python-is-python3 python3.10-venv lsof spi-tools vim mtd-utils jq rsync libffi-dev jq python3-pip python3-rrdtool python3.10-venv wget swig build-essential python3-dev
if [[ $? -eq 2 ]]; then echo "Error, step failed..."; fi

echo "Upgrade pip to latest available version"
python3 -m pip install --upgrade pip
python3 -m pip install setuptools_scm yq

echo "Adding GPIO user and fixing gpiochip permissions"
groupadd gpio
usermod -aG gpio pico
chgrp gpio /dev/gpiochip*
chmod 660 /dev/gpiochip*
chgrp gpio /dev/spidev*
chmod 660 /dev/spidev*

if grep -q '^luckfox-config load$' /etc/rc.local && ! grep -q 'luckfox.cfg.clean' /etc/rc.local; then
    echo "Ensuring rc.local sanitizes /etc/luckfox.cfg before applying Luckfox settings"
    sed -i '/^luckfox-config load$/i \
if [ -f /etc/luckfox.cfg ]; then\
    tr -d '\''\\000'\'' </etc/luckfox.cfg > /tmp/luckfox.cfg.clean\
    install -m 0644 /tmp/luckfox.cfg.clean /etc/luckfox.cfg\
    rm -f /tmp/luckfox.cfg.clean\
fi' /etc/rc.local
fi

echo "Adding chgrp to rc.local - hacky but it works"
echo "chgrp gpio /dev/gpiochip* 2>/dev/null || true" >> /etc/rc.local
echo "chmod 660 /dev/gpiochip* 2>/dev/null || true" >> /etc/rc.local
echo "chgrp gpio /dev/spidev* 2>/dev/null || true" >> /etc/rc.local
echo "chmod 660 /dev/spidev* 2>/dev/null || true" >> /etc/rc.local

echo "Finally run an apt upgrade for any packages that need/want upgrading"
apt upgrade -y --option Dpkg::Options::="--force-confold"

reboot
