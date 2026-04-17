#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    show_error "Installation requires root privileges.\n\nPlease run: sudo $0"
    exit 1
fi

CURRENT_MODEL="$(tr -d '\0' </proc/device-tree/model)"
case "$CURRENT_MODEL" in
    "Luckfox Pico Ultra W"|"Luckfox Pico Pi A W"|"Luckfox Pico Pi B W")
        HAS_WIFI_BT=1
        ;;
    *)
        HAS_WIFI_BT=0
        ;;
esac

echo "Disable root user password"
passwd -l root

echo "Force user password change on next login"
passwd --expire pico

echo "Injecting the ability to manually enable/disable the things we need to in the luckfox-config script"
sudo sed -i '/elif \[ -z "\$1" \]; then/i \
elif [ "$1" == "rgb_disable" ]; then\
    luckfox_config_init\
    LF_GUI_ENABLE=0\
    luckfox_rgb_app 0\
elif [ "$1" == "spi_enable" ]; then\
    luckfox_config_init\
    LF_GUI_ENABLE=0\
    luckfox_i2c_app 0 4 1\
    luckfox_spi_app 1 0 0 1 1 1000000\
    echo "SPI Enabled - Reboot for changes to take effect"\
elif [ "$1" == "uart_disable" ]; then\
    luckfox_uart_app 0 $2 $3\
elif [ "$1" == "uart_enable" ]; then\
    luckfox_uart_app 1 $2 $3\
' /usr/bin/luckfox-config

if [[ "$CURRENT_MODEL" == "Luckfox Pico Ultra"* ]]; then
    echo "Disabling RGB"
    luckfox-config rgb_disable
else
    echo "Skipping RGB disable for $CURRENT_MODEL"
fi

echo "Increase the size of the tmpfs"
mount -o remount,size=32M /run
echo "tmpfs /run tmpfs rw,nodev,nosuid,size=32M 0 0" | tee -a /etc/fstab

echo "Regenerating SSH keys"
rm /etc/ssh/ssh_host_*
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
chmod 600 /etc/ssh/ssh_host_*_key
chmod 644 /etc/ssh/ssh_host_*_key.pub
chown root:root /etc/ssh/ssh_host_*
systemctl restart ssh

echo "Disable all the services that we're not going to need"
systemctl disable --now acpid
systemctl disable --now acpid.socket
systemctl disable --now alsa-restore.service
systemctl disable --now alsa-state.service
systemctl disable --now apt-daily.timer
systemctl disable --now apt-daily-upgrade.timer
systemctl disable --now luckfox_switch_rgb_resolution.service 2>/dev/null || pkill -f luckfox_switch_rgb_resolution
systemctl disable --now ModemManager.service
systemctl disable --now rsyslog.service
systemctl disable --now smbd nmbd # samba services, can be enabled via menu
systemctl disable --now sound.target
systemctl disable --now systemd-pstore.service
systemctl disable --now veritysetup.target
systemctl disable --now vsftpd.service
systemctl disable --now serial-getty@ttyFIQ0

echo "Prepare the switch to networkd"
networkfile="/etc/systemd/network/10-wired.network"
mac="$(awk '/Serial/ {print $3}' /proc/cpuinfo | tail -c 11 | sed 's/^\(.*\)/a2\1/' | sed 's/\(..\)/\1:/g;s/:$//')"
cat << EOF > $networkfile
[Match]
Name=eth0
[Link]
MACAddress=$mac
[Network]
DHCP=yes
[DHCPv4]
ClientIdentifier=mac
RouteMetric=10
EOF

echo "Configure systemd-networkd to take effect on next boot"
systemctl disable NetworkManager
systemctl disable NetworkManager-dispatcher
systemctl disable NetworkManager-wait-online
systemctl enable systemd-networkd

echo "Kill the /etc/network folder as NetworkManager isn't used anymore and systemd-networkd doesn't need it"
rm -rf /etc/network

echo "Update apt"
apt update

echo "Purge unneeded packages"
apt remove -y --purge \
    acpid \
    adwaita-icon-theme \
    alsa-topology-conf \
    alsa-utils \
    at-spi2-core \
    can-utils \
    dconf-gsettings-backend \
    dconf-service \
    dnsmasq-base \
    evemu-tools \
    evtest \
    fonts-dejavu-core \
    fonts-noto-color-emoji \
    gsettings-desktop-schemas \
    gstreamer* \
    guvcview \
    hicolor-icon-theme \
    humanity-icon-theme \
    ifupdown \
    iperf3 \
    isc-dhcp-client \
    libao* \
    libasound2* \
    libav* \
    libgtk-3-0 \
    libgtk-3-bin \
    libgtk-3-common \
    libpulse* \
    libsox* \
    libv4l* \
    libwayland* \
    libx11* \
    mesa-va-drivers \
    mesa-vdpau-drivers \
    modemmanager \
    network-manager \
    network-manager-pptp \
    packagekit \
    packagekit-tools \
    ppp \
    pptp-linux \
    rsyslog \
    sox \
    tcpdump \
    ubuntu-mono \
    usb-modeswitch \
    usb-modeswitch-data \
    uvcdynctrl* \
    va-driver-all \
    vdpau-driver-all \
    vsftpd \
    x11-common \
    xauth \
    xdg-user-dirs \
    xinput \
    xkb-data

apt autoremove -y --purge
apt autoclean

echo "Disable the NPU - we don't need it"
rm /oem/usr/ko/insmod_ko.sh

echo "Disable the rgb switcher starting in rc.local"
sed -i 's/\/usr\/bin\/luckfox_switch_rgb_resolution/#\/usr\/bin\/luckfox_switch_rgb_resolution/' /etc/rc.local


if [ "$HAS_WIFI_BT" -ne 1 ]; then
    echo "Disable the wifi/bt script - we won't be using them"
    sed -i 's/wifibt_init/#wifibt_init/' /etc/rc.local
fi

echo "Install u-boot-tools and configure fw_env.config"
apt install -y u-boot-tools
echo "Creating fw_env.config (Luckfox standard env partition)"
cat <<EOF > /etc/fw_env.config
/dev/mmcblk0p1  0x0  0x8000
EOF

echo "Configure bootargs to reduce CMA allocation to 1M (We don't need it)"
fw_setenv sys_bootargs "`fw_printenv|grep 'sys_bootargs'|sed 's/rk_dma_heap_cma=..M/rk_dma_heap_cma=1M/'|sed 's/sys_bootargs=//'`"

echo "Trim the logging time to 1d"
journalctl --vacuum-time=1d

echo ""
echo "### SYSTEM CONFIG COMPLETE ###"
echo "#### NOTE IP AND SSH IDENTITY WILL CHANGE ON RESTART ####"

reboot
