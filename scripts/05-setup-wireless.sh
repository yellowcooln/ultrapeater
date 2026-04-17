#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    show_error "Installation requires root privileges.\n\nPlease run: sudo $0"
    exit 1
fi

echo "### ULTRAPEATER WIFI SETUP SCRIPT ###"
echo "This board's onboard Wi-Fi only supports 2.4GHz networks."
echo "If you are using the onboard wireless adapter, do not choose a 5GHz-only SSID."

echo "Installing Packages"
apt install -y wpasupplicant

echo "Configure the networkd DHCP client for Wifi"
networkfile="/etc/systemd/network/20-wireless.network"
cat << EOF > $networkfile
[Match]
Name=wlan0
[Link]
RequiredForOnline=routable
[Network]
DHCP=yes
IgnoreCarrierLoss=3s
[DHCPv4]
RouteMetric=100
EOF

systemctl restart systemd-networkd

wifi_bt_init.sh

sleep 2
echo "Scanning for networks"
wpa_cli -i wlan0 scan
sleep 5
wpa_cli -i wlan0 scan_results

cat <<'EOF' > /etc/wpa_supplicant.conf
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
country=AU
EOF

while true; do
    read -p "Enter a 2.4GHz wifi network name (Case Sensitive): " network
    read -s -p "Enter the wifi network passphrase: " passphrase
    echo ""
    wpa_passphrase "$network" "$passphrase" >> /etc/wpa_supplicant.conf

    read -p "Add another SSID for failover/portable use? [y/N]: " add_another
    case "$add_another" in
        y|Y|yes|YES)
            ;;
        *)
            break
            ;;
    esac
done
echo ""

killall wpa_supplicant

wifi_bt_init.sh

wpa_cli -i wlan0 reconfigure
networkctl reconfigure wlan0

echo "Configured Wi-Fi profiles saved to /etc/wpa_supplicant.conf"
echo "wpa_supplicant will automatically scan and move to another saved SSID if the current one is unavailable."
