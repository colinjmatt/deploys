#!/bin/bash

# Define paths
INSTALL_DIR="/opt/flaresolverr"
BACKUP_DIR="/tmp/flaresolverr_backup"
PACKAGE_JSON="$INSTALL_DIR/package.json"
FLARESOLVERR_SERVICE="flaresolverr.service"

# Function to stop and start service
manage_service() {
    local action=$1
    sudo systemctl $action $FLARESOLVERR_SERVICE
}

# Get current installed version using grep and sed
if [ -f "$PACKAGE_JSON" ]; then
    CURRENT_VERSION=$(grep '"version"' "$PACKAGE_JSON" | sed -E 's/.*"version": "([^"]+)".*/\1/')
else
    echo "Error: package.json not found!"
    exit 1
fi

# Fetch latest version info from GitHub
LATEST_URL=$(curl -sSL https://api.github.com/repos/FlareSolverr/FlareSolverr/releases | grep -o 'https://.*\.tar\.gz' | awk 'NR==1')
LATEST_VERSION=$(echo "$LATEST_URL" | grep -oP '(?<=download/v)\d+\.\d+\.\d+')

# Compare versions
if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo "FlareSolverr is already up-to-date (version $CURRENT_VERSION)."
    exit 0
elif [ -z "$LATEST_VERSION" ]; then
    echo "Error: Could not fetch the latest version."
    exit 1
fi

# Stop the service before updating
manage_service stop

# Backup current installation
echo "Backing up current version ($CURRENT_VERSION) to $BACKUP_DIR..."
rm -rf "$BACKUP_DIR"
mv "$INSTALL_DIR" "$BACKUP_DIR"

# Download and extract new version
echo "Downloading and installing FlareSolverr version $LATEST_VERSION..."
mkdir -p "$INSTALL_DIR"
if curl -sSL "$LATEST_URL" | tar -xz -C "$INSTALL_DIR"; then
    echo "FlareSolverr updated successfully to version $LATEST_VERSION."
    manage_service start
else
    echo "Error: Failed to install FlareSolverr. Restoring backup..."
    rm -rf "$INSTALL_DIR"
    mv "$BACKUP_DIR" "$INSTALL_DIR"
    manage_service start
    exit 1
fi

echo "Update completed successfully."
exit 0