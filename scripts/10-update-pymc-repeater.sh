#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    show_error "Installation requires root privileges.\n\nPlease run: sudo $0"
    return
fi

systemctl stop pymc-repeater

PYMC_SCRIPT_DIR="/tmp/pymc_repeater_install"
PYMC_CORE_DIR="/tmp/pymc_core_install"
PYMC_INSTALL_DIR="/opt/pymc_repeater"
PYMC_CONFIG_DIR="/etc/pymc_repeater"
PYMC_LOG_DIR="/var/log/pymc_repeater"
PYMC_SERVICE_USER="repeater"
PYMC_SERVICE_NAME="pymc-repeater"
PYMC_SERVICE_USER_HOME="/var/lib/pymc_repeater"
PYMC_REPO_URL="https://github.com/rightup"        
PYMC_REPO_BRANCH="${1:-dev}"
PYMC_CORE_REPO_BRANCH="${1:-dev}"

echo "# Cleaning old pyMC Repeater installation files..."
# Remove old repeater directory to ensure clean install
rm -rf "$PYMC_INSTALL_DIR" 2>/dev/null || true
rm -rf "$PYMC_SCRIPT_DIR" 2>/dev/null || true

echo "# Clone pyMC Core"
git clone --single-branch --branch $PYMC_CORE_REPO_BRANCH $PYMC_REPO_URL/pyMC_Core.git $PYMC_CORE_DIR
cd $PYMC_CORE_DIR

echo "Prepare pip"
cd "$PYMC_CORE_DIR"
# Suppress pip root user warnings
export PIP_ROOT_USER_ACTION=ignore

echo "# Installing core"
python3 -m pip install --break-system-packages .

echo "# Clone pyMC Repeater"
git clone --single-branch --branch $PYMC_REPO_BRANCH $PYMC_REPO_URL/pyMC_Repeater.git $PYMC_SCRIPT_DIR
cd $PYMC_SCRIPT_DIR

echo "# Generating pyMC_Repeater version file..."
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
cp "$PYMC_SCRIPT_DIR/radio-presets.json" $PYMC_SERVICE_USER_HOME/ 2>/dev/null || truezx

echo "# Setting permissions..."
chown -R "$PYMC_SERVICE_USER:$PYMC_SERVICE_USER" "$PYMC_INSTALL_DIR" "$PYMC_CONFIG_DIR" "$PYMC_LOG_DIR" $PYMC_SERVICE_USER_HOME
chmod 750 "$PYMC_CONFIG_DIR" "$PYMC_LOG_DIR" $PYMC_SERVICE_USER_HOME
# Ensure the service user can create subdirectories in their home directory
chmod 755 $PYMC_SERVICE_USER_HOME
# Pre-create the .config directory that the service will need
mkdir -p $PYMC_SERVICE_USER_HOME/.config/pymc_repeater
chown -R "$PYMC_SERVICE_USER:$PYMC_SERVICE_USER" $PYMC_SERVICE_USER_HOME/.config

echo "# Installing dependencies and pyMC_Repeater"
cd "$PYMC_SCRIPT_DIR"
# Suppress pip root user warnings
export PIP_ROOT_USER_ACTION=ignore
# Calculate version from git for setuptools_scm
if [ -d .git ]; then
    git fetch --tags 2>/dev/null || true
    GIT_VERSION=$(python3 -m setuptools_scm 2>/dev/null || echo "1.0.5")
    export SETUPTOOLS_SCM_PRETEND_VERSION="$GIT_VERSION"
    echo "Installing version: $GIT_VERSION"
else
    export SETUPTOOLS_SCM_PRETEND_VERSION="1.0.5"
fi

python3 -m pip install --break-system-packages .

systemctl start pymc-repeater

echo "Clean up install files"
rm -rf $PYMC_SCRIPT_DIR
rm -rf $PYMC_CORE_DIR
