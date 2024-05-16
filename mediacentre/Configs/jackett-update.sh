#!/bin/bash

# Function to compare version numbers
version_compare() {
  if [[ $1 != "$2" ]]; then
      stop_jackett
      update_jackett "$2"
      start_jackett
  fi
}

# Function to stop Jackett service
stop_jackett() {
  systemctl stop jackett
}

# Function to start Jackett service
start_jackett() {
  systemctl start jackett
}

# Function to update Jackett
update_jackett() {
  # Define paths
  install_dir="/opt/jackett"
  temp_dir="/tmp/jackett_backup"

  # Backup the current installation
  mv "$install_dir" "$temp_dir"

  # Download the latest release from GitHub, extract it, and copy to /opt/
  if curl -s -L "https://github.com/Jackett/Jackett/releases/download/$1/Jackett.Binaries.LinuxAMDx64.tar.gz" | tar -xz -C /opt/; then
    # Rename installation directory to lowercase
    mv "/opt/Jackett" "$install_dir"
    # Change ownership recursively to jackett:jackett
    chown -R jackett:jackett "$install_dir"
  else
    # Restore previous installation from backup
    mv "$temp_dir" "$install_dir"
    echo "Update failed. Restored previous installation."
  fi
}

# Fetch the latest release version from GitHub API
response=$(curl -s "https://api.github.com/repos/Jackett/Jackett/releases/latest")
latest_version=$(echo "$response" | grep -o '"tag_name": ".*"' | cut -d'"' -f4)

# Get the installed version of Jackett
installed_version=$(/opt/jackett/jackett --version | awk '{print $2}')

# Compare versions
version_compare "$installed_version" "$latest_version"