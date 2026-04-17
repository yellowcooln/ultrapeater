# Ultrapeater

This branch contains the Luckfox Pico Pi A W port for the MeshSmith 1W setup. It is intended to run pyMC_Repeater on the Luckfox Ubuntu image with the onboard Wi-Fi and optional LTE used for network access.

More information at https://zindello.com.au/ultrapeater

## Target Hardware

- Luckfox Pico Pi A W
- MeshSmith 1W radio hat
- Luckfox Ubuntu image

This branch is not the stock UltraPeater setup. It changes the scripts to better match the Pico Pi target and leaves radio board selection to pyMC_Repeater rather than installing this repo's old UltraPeater board override.

## Getting started

Flash the Luckfox Pico Pi Ubuntu image first:

https://wiki.luckfox.com/Luckfox-Pico-Pi/

Once flashed, get the board's IP from your router and log in over SSH with the default credentials:

- user: `pico`
- password: `luckfox`

The hostname will usually show up as `luckfox`.

### IMPORTANT: USE THE UBUNTU IMAGE NOT THE BUILDROOT IMAGE

The IP address and SSH host identity will change after running script `01`, so it is safest to connect the first time with:

``` bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null pico@<ip_to_device>
```

## Software Installation

Clone this fork and branch to the `pico` home directory:

``` bash
git clone --branch pico-pi-meshsmith https://github.com/yellowcooln/ultrapeater.git
```

All setup scripts should be run with `sudo`.

### Script 1 01-luckfox-system-config.sh

``` bash
sudo bash ultrapeater/scripts/01-luckfox-system-config.sh
```

This script:
- prepares the base system for the Luckfox Ubuntu image
- injects the non-interactive `luckfox-config` helpers used by later scripts
- disables RGB handling on Ultra boards only
- regenerates SSH keys
- disables unneeded services and switches the box to `systemd-networkd`
- configures Ethernet with a preferred route metric
- reboots at the end

It runs quickly, with a short pause during SSH key regeneration.

### NOTE: The system IP address will usually change at this point.

### Script 2 02-luckfox-system-update.sh

``` bash
sudo bash ultrapeater/scripts/02-luckfox-system-update.sh
```

This script:
- updates the Ubuntu image packages
- installs the main build and runtime dependencies
- configures GPIO and SPI device permissions
- enables the hardware functions needed by the radio stack
- reboots at the end

This is one of the slower steps because it upgrades the base image packages.

### Script 3 03-install-pymc-repeater.sh

``` bash
sudo bash ultrapeater/scripts/03-install-pymc-repeater.sh
```

This script installs pyMC_Repeater and sets up the service.

Important behavior on this branch:
- it installs the `dev` branch of `rightup/pyMC_Repeater` unless you pass a branch name as the first argument
- it does not install a local `radio-settings.json` override
- MeshSmith radio configuration is expected to come from pyMC_Repeater itself

This is usually the longest-running step because it installs Python dependencies and builds the required packages.

### Script 4 04-install-pymc-console.sh

``` bash
sudo bash ultrapeater/scripts/04-install-pymc-console.sh
```

This script installs pyMC_Console, which can be selected from the UI as an alternative console.

This step is relatively quick.

### Script 5 05-setup-wireless.sh

``` bash
sudo bash ultrapeater/scripts/05-setup-wireless.sh
```

This script configures onboard Wi-Fi.

Behavior:
- warns that the onboard radio only supports `2.4GHz` Wi-Fi
- scans for visible networks
- prompts for SSID and passphrase
- allows multiple saved SSIDs for portable use
- configures Wi-Fi as preferred over LTE, but lower priority than wired Ethernet

`wpa_supplicant` will automatically try other saved SSIDs if the current one disappears.

### Script 6 06-setup-lte.sh

``` bash
sudo bash ultrapeater/scripts/06-setup-lte.sh
```

This script prepares optional LTE in NDIS mode on the Pico Pi.

Behavior:
- configures `usb0` for DHCP with a high route metric
- keeps LTE as a failover path behind Ethernet and Wi-Fi
- checks whether USB is already in host mode
- launches `luckfox-config` so you can enable USB host mode and `4G Module -> NDIS`
- verifies that `usb0` appears and receives an address

LTE is intended to be the last-resort network path, not the primary one.

## Update Scripts

### DEPRECATED - 10-update-pymc-repeater.sh

This script is deprecated and not part of the normal flow for this branch.

Only use it if you are dealing with an older install that explicitly still needs that migration path.

### To update pymc-console simply run the 04-install-pymc-console.sh script again


## BUGFIX Scripts

### Polkit and Web Upgrade fix - 99-01-fix-polkit-and-ota-update.sh

This script fixes the service not restarting properly from the web UI, and also fixes the issue of OTA updates not working. Run this script to allow upgrading of pyMC Repeater from the web UI.

## Login

Once the installation is complete, you can log in to the pyMC Repeater UI at:

``` text
https://<device_ip>:8000/
```

On this branch, board-specific radio configuration should come from pyMC_Repeater rather than this repo's old UltraPeater override file.

## Credit

Credit must go to @theshaun for his work he did on the Femto, a lot of these scripts have leaned heavily into the work that he did there, as well as a lot of the general work done by @RightUp and the team on pyMC_Repeater.
