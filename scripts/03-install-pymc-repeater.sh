#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    show_error "Installation requires root privileges.\n\nPlease run: sudo $0"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PYMC_SCRIPT_DIR="/tmp/pymc_repeater_install"
PYMC_INSTALL_DIR="/opt/pymc_repeater"
PYMC_CONFIG_DIR="/etc/pymc_repeater"
PYMC_LOG_DIR="/var/log/pymc_repeater"
PYMC_SERVICE_USER="repeater"
PYMC_SERVICE_NAME="pymc-repeater"
PYMC_SERVICE_USER_HOME="/var/lib/pymc_repeater"
PYMC_REPO_URL="https://github.com/rightup/pyMC_Repeater.git"        
PYMC_REPO_BRANCH="${1:-dev}"
PYMC_CONFIG_FILE="/etc/pymc_repeater/config.yaml"

echo "# Creating service user..."
useradd --system --home $PYMC_SERVICE_USER_HOME --shell /sbin/nologin "$PYMC_SERVICE_USER"

echo "# Adding user to hardware groups..."
usermod -a -G gpio "$PYMC_SERVICE_USER" 2>/dev/null || true

echo "# Cleaning old pyMC Repeater installation files..."
# Remove old repeater directory to ensure clean install
rm -rf "$PYMC_INSTALL_DIR" 2>/dev/null || true
rm -rf "$PYMC_SCRIPT_DIR" 2>/dev/null || true
rm -rf "$PYMC_CONFIG_DIR" 2>/dev/null || true

echo "# Creating directories..."
mkdir -p "$PYMC_INSTALL_DIR" "$PYMC_CONFIG_DIR" "$PYMC_LOG_DIR" $PYMC_SERVICE_USER_HOME

echo "# clone pyMC Repeater"
git clone --single-branch --branch $PYMC_REPO_BRANCH $PYMC_REPO_URL $PYMC_SCRIPT_DIR
cd $PYMC_SCRIPT_DIR

echo "# Generating version file..."
# Generate version file using setuptools_scm before copying
if [ -d .git ]; then
    git fetch --tags 2>/dev/null || true
    # Write the version file that will be copied
    GENERATED_VERSION=$(python3 -m setuptools_scm 2>&1 || echo "unknown (setuptools_scm not available)")
    python3 -c "from setuptools_scm import get_version; get_version(write_to='repeater/_version.py')" 2>&1 || echo "    Warning: Could not generate _version.py file"
    echo "    Generated version: $GENERATED_VERSION"
fi

echo "# Setting up installation files"
cp -r "$PYMC_SCRIPT_DIR/repeater" "$PYMC_INSTALL_DIR/"
cp "$PYMC_SCRIPT_DIR/pyproject.toml" "$PYMC_INSTALL_DIR/"
cp "$PYMC_SCRIPT_DIR/README.md" "$PYMC_INSTALL_DIR/"
cp "$PYMC_SCRIPT_DIR/manage.sh" "$PYMC_INSTALL_DIR/" 2>/dev/null || true
cp "$PYMC_SCRIPT_DIR/pymc-repeater.service" "$PYMC_INSTALL_DIR/" 2>/dev/null || true
cp "$PYMC_SCRIPT_DIR/radio-presets.json" $PYMC_SERVICE_USER_HOME 2>/dev/null || true

echo "# Installing configuration..."
cp "$PYMC_SCRIPT_DIR/config.yaml.example" "$PYMC_CONFIG_DIR/config.yaml.example"
if [ ! -f "$PYMC_CONFIG_DIR/config.yaml" ]; then
    cp "$PYMC_SCRIPT_DIR/config.yaml.example" "$PYMC_CONFIG_DIR/config.yaml"
fi

echo "# Enable GPIOd to prevent errors on first start"
sed -i "/^  cs_pin:.*/a\\  gpio_chip: 1" "$PYMC_CONFIG_FILE"
sed -i "/^  gpio_chip:.*/a\\  use_gpiod_backend: true" "$PYMC_CONFIG_FILE"

echo "# Leaving radio-settings.json under pyMC_Repeater control"
echo "  No local board config override will be installed."

echo "# Copy in our custom OTA update script"
cp $SCRIPT_DIR/assets/pymc-do-upgrade /usr/local/bin/pymc-do-upgrade
chmod +x /usr/local/bin/pymc-do-upgrade

echo "# Setting permissions..."
chown -R "$PYMC_SERVICE_USER:$PYMC_SERVICE_USER" "$PYMC_INSTALL_DIR" "$PYMC_CONFIG_DIR" "$PYMC_LOG_DIR" "$PYMC_SERVICE_USER_HOME"
chmod 750 "$PYMC_CONFIG_DIR" "$PYMC_LOG_DIR" $PYMC_SERVICE_USER_HOME
# Ensure the service user can create subdirectories in their home directory
chmod 755 $PYMC_SERVICE_USER_HOME
# Pre-create the .config directory that the service will need
mkdir -p $PYMC_SERVICE_USER_HOME/.config/pymc_repeater
chown -R "$PYMC_SERVICE_USER:$PYMC_SERVICE_USER" $PYMC_SERVICE_USER_HOME/.config

echo "# Installing dependencies and pyMC_Repeater"

cd "$PYMC_SCRIPT_DIR"
echo "# Creating Python virtual environment..."
python3 -m venv "$PYMC_INSTALL_DIR/venv"

# Calculate version from git for setuptools_scm
if [ -d .git ]; then
    git fetch --tags 2>/dev/null || true
    GIT_VERSION=$(python3 -m setuptools_scm 2>/dev/null || echo "1.0.5")
    export SETUPTOOLS_SCM_PRETEND_VERSION="$GIT_VERSION"
    echo "Installing version: $GIT_VERSION"
else
    export SETUPTOOLS_SCM_PRETEND_VERSION="1.0.5"
fi

"$PYMC_INSTALL_DIR/venv/bin/pip" install --upgrade pip setuptools wheel
"$PYMC_INSTALL_DIR/venv/bin/pip" install --force-reinstall --no-cache-dir .

echo "# Installing systemd service..."
cp "$PYMC_SCRIPT_DIR/pymc-repeater.service" /etc/systemd/system/
systemctl daemon-reload

# Configure polkit for passwordless service restart
mkdir -p /etc/polkit-1/localauthority/50-local.d
cat > /etc/polkit-1/localauthority/50-local.d/10-pymc-repeater.pkla <<'EOF'
[Allow repeater to restart pymc-repeater service]
Identity=unix-user:repeater
Action=org.freedesktop.systemd1.manage-units
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
chmod 0644 /etc/polkit-1/localauthority/50-local.d/10-pymc-repeater.pkla

echo "# Configuring sudoers for service management..."
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/pymc-repeater <<'EOF'
# Allow repeater user to manage the pymc-repeater service without password
repeater ALL=(root) NOPASSWD: /usr/bin/systemctl restart pymc-repeater, /usr/bin/systemctl stop pymc-repeater, /usr/bin/systemctl start pymc-repeater, /usr/bin/systemctl status pymc-repeater, /usr/local/bin/pymc-do-upgrade
EOF
chmod 0440 /etc/sudoers.d/pymc-repeater

echo "Enable pyMC_Repeater start on boot"
systemctl enable pymc-repeater
systemctl start pymc-repeater

echo "Clean up install files"
rm -rf $PYMC_SCRIPT_DIR
