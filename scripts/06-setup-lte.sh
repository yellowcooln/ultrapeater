#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    show_error "Installation requires root privileges.\n\nPlease run: sudo $0"
    exit 1
fi

if ! command -v luckfox-config >/dev/null 2>&1; then
    echo "luckfox-config was not found in PATH."
    echo "This script requires the Luckfox Ubuntu image with luckfox-config installed."
    exit 1
fi

echo "### ULTRAPEATER LTE SETUP SCRIPT ###"
echo "This script prepares the Luckfox Pico Pi for LTE in NDIS mode."
echo "LTE is configured as a failover path and should only be used when wired or Wi-Fi are unavailable."
echo ""
echo "Before continuing:"
echo "1. Power the board off before inserting or removing the SIM, antenna, or 4G module."
echo "2. Set the left mode switch to 1, then to KE, so the USB M.2 interface is active for 4G."
echo "3. Make sure you have another management path available after USB is switched to HOST."
echo "   Type-C data mode is not available while the board is in USB HOST mode."
echo ""

LTE_NETWORK_FILE="/etc/systemd/network/30-lte-usb0.network"
USB_MODE_FILE="/sys/devices/platform/ff3e0000.usb2-phy/otg_mode"

echo "Configuring systemd-networkd for the LTE modem interface..."
cat <<'EOF' > "$LTE_NETWORK_FILE"
[Match]
Name=usb0

[Link]
RequiredForOnline=no

[Network]
DHCP=yes
IgnoreCarrierLoss=3s

[DHCPv4]
RouteMetric=300
UseDNS=yes
EOF

systemctl restart systemd-networkd

if [ -f "$USB_MODE_FILE" ]; then
    CURRENT_USB_MODE="$(cat "$USB_MODE_FILE")"
    echo "Current USB mode: $CURRENT_USB_MODE"
else
    CURRENT_USB_MODE="unknown"
    echo "USB mode file not found; continuing without a direct USB mode check."
fi

if [ "$CURRENT_USB_MODE" != "host" ]; then
    echo ""
    echo "USB mode is not currently set to host."
    echo "The Luckfox docs require USB HOST mode before the 4G module can be used."
    echo ""
    echo "luckfox-config will open now."
    echo "Set: Advanced Options -> USB -> host"
    echo "Then exit luckfox-config and reboot if it asks you to."
    read -p "Press Enter to open luckfox-config..."
    luckfox-config
    echo ""
    echo "If you changed USB mode to host, reboot the board now and run this script again."
    exit 0
fi

echo ""
echo "USB is already in host mode."
echo "luckfox-config will open now for LTE setup."
echo "Set: 4G Module -> enable -> NDIS mode"
echo "Then save and exit."
read -p "Press Enter to open luckfox-config..."
luckfox-config

echo ""
echo "Checking for 4G modem device nodes..."
sleep 3
ls /dev/ttyUSB* 2>/dev/null || echo "No /dev/ttyUSB* nodes found yet."

echo ""
echo "Checking for the usb0 network interface..."
for _ in $(seq 1 15); do
    if ip link show usb0 >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! ip link show usb0 >/dev/null 2>&1; then
    echo "usb0 was not detected."
    echo "Verify the board switch is set to 1 then KE, the module is seated correctly, and the SIM is valid."
    echo "Helpful checks:"
    echo "  lsusb"
    echo "  dmesg | grep ttyUSB"
    exit 1
fi

echo "usb0 detected. Requesting network configuration..."
ip link set usb0 up
networkctl reconfigure usb0 2>/dev/null || true

echo ""
echo "Waiting for an IPv4 address on usb0..."
for _ in $(seq 1 15); do
    if ip -4 addr show usb0 | grep -q "inet "; then
        break
    fi
    sleep 2
done

echo ""
ip addr show usb0
echo ""
echo "Route preference is set so wired is preferred first, Wi-Fi second, and LTE last."
echo "If another network is available, systemd-networkd should keep LTE as the backup path."

if ip -4 addr show usb0 | grep -q "inet "; then
    echo ""
    echo "LTE NDIS setup looks good."
    echo "The modem interface is up on usb0 and has an IPv4 address."
else
    echo ""
    echo "usb0 is present, but no IPv4 address was assigned yet."
    echo "Check carrier activation, SIM status, module registration, and luckfox-config LTE settings."
fi
