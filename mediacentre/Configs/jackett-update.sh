#!/bin/bash

# Define paths
INSTALL_DIR="/opt/jackett"
BACKUP_DIR="/tmp/jackett_backup"
JACKETT_SERVICE="jackett.service"

# Function to stop and start service
manage_service() {
    local action=$1
    sudo systemctl $action $JACKETT_SERVICE
}

# Get current installed version (strip "v" and trim any whitespace or newlines)
if [ -x "$INSTALL_DIR/jackett" ]; then
    CURRENT_VERSION=$($INSTALL_DIR/jackett --version | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | tr -d 'v' | tr -d '\n')
else
    echo "Error: Jackett executable not found in $INSTALL_DIR!"
    exit 1
fi

# Fetch the latest version info from GitHub API (strip "v" from the latest version)
response=$(curl -s "https://api.github.com/repos/Jackett/Jackett/releases/latest")
LATEST_VERSION=$(echo "$response" | grep -o '"tag_name": ".*"' | cut -d'"' -f4 | tr -d 'v')

# Compare versions
if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo "Jackett is already up-to-date (version $CURRENT_VERSION)."
    exit 0
elif [ -z "$LATEST_VERSION" ]; then
    echo "Error: Could not fetch the latest version."
    exit 1
fi

# Stop the Jackett service before updating
manage_service stop

# Backup current installation
echo "Backing up current version ($CURRENT_VERSION) to $BACKUP_DIR..."
rm -rf "$BACKUP_DIR"
mv "$INSTALL_DIR" "$BACKUP_DIR"

# Download and extract the latest release
echo "Downloading and installing Jackett version $LATEST_VERSION..."
mkdir -p "$INSTALL_DIR"
if curl -s -L "https://github.com/Jackett/Jackett/releases/download/v$LATEST_VERSION/Jackett.Binaries.LinuxAMDx64.tar.gz" | tar -xz --strip-components=1 -C "$INSTALL_DIR"; then
    # Set proper ownership
    chown -R jackett:jackett "$INSTALL_DIR"
    echo "Jackett updated successfully to version $LATEST_VERSION."
    manage_service start
else
    echo "Error: Failed to install Jackett. Restoring previous installation..."
    rm -rf "$INSTALL_DIR"
    mv "$BACKUP_DIR" "$INSTALL_DIR"
    manage_service start
    exit 1
fi

echo "Update completed successfully."
exit 0