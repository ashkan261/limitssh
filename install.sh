#!/bin/bash

# Function to check if a package is installed
is_package_installed() {
  dpkg -l | grep -q $1
}

# Function to determine the package manager
determine_package_manager() {
  if command -v apt-get >/dev/null; then
    echo "apt-get"
  elif command -v yum >/dev/null; then
    echo "yum"
  else
    echo "Neither apt-get nor yum package manager found."
    exit 1
  fi
}

# Function to install packages based on the package manager
install_packages() {
  PACKAGE_MANAGER=$(determine_package_manager)
  if [ "$PACKAGE_MANAGER" == "apt-get" ]; then
    sudo apt-get update -y
    sudo apt-get install $@ -y
  elif [ "$PACKAGE_MANAGER" == "yum" ]; then
    sudo yum update -y
    sudo yum install -y $@
  fi
}

# Function to install PHP based on the package manager
install_php() {
  if ! is_package_installed php; then
    echo "PHP is not installed. Installing PHP..."
    install_packages php
  else
    echo "PHP is already installed."
  fi
}

# Function to install Nethogs if not already installed
install_nethogs() {
  if [ ! -x "/usr/local/sbin/nethogs" ]; then
    echo "Updating and installing required packages..."
    if [ "$PACKAGE_MANAGER" == "apt-get" ]; then
      install_packages build-essential libncurses5-dev libncursesw5-dev libpcap-dev make zip unzip wget
    elif [ "$PACKAGE_MANAGER" == "yum" ]; then
      install_packages ncurses-devel gcc-c++ libpcap-devel.x86_64 libpcap.x86_64 "ncurses*"
    fi

    # Download and extract nethogs
    NETHOGS_ZIP_URL="https://github.com/xpanel-cp/Nethogs-Json-main/archive/refs/heads/master.zip"
    NETHOGS_ZIP="/tmp/nethogs.zip"
    NETHOGS_DIR="/tmp/nethogs"

    echo "Downloading nethogs..."
    sudo wget -O "$NETHOGS_ZIP" "$NETHOGS_ZIP_URL" || { echo "Error: Failed to download nethogs." && exit 1; }

    echo "Extracting nethogs..."
    sudo unzip "$NETHOGS_ZIP" -d "/tmp" || { echo "Error: Failed to extract nethogs." && exit 1; }
    EXTRACTED_DIR=$(sudo ls /tmp | grep "Nethogs-Json-main")
    sudo mv "/tmp/$EXTRACTED_DIR" "$NETHOGS_DIR"

    # Build and install nethogs
    echo "Building and installing nethogs..."
    cd "$NETHOGS_DIR" || { echo "Error: Failed to change directory to $NETHOGS_DIR" && exit 1; }
    sudo chmod +x determineVersion.sh
    sudo make install || { echo "Error: Failed to build and install nethogs." && exit 1; }
    sudo cp /usr/local/sbin/nethogs /usr/sbin/nethogs

    # Clean up
    echo "Cleaning up..."
    sudo rm -rf "$NETHOGS_ZIP" "$NETHOGS_DIR"

    # Set capabilities
    echo "Setting capabilities..."
    sudo setcap "cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe" /usr/local/sbin/nethogs || { echo "Error: Failed to set capabilities." && exit 1; }

    # Update system PATH
    hash -r

    echo "Installation complete!"
  else
    echo "Nethogs is already installed."
  fi
}

# Function to add cron job
add_cron_job() {
  # Get the PHP path
  php_path=$(which php)

  # Get the directory of this script
  script_dir="/home/ubuntu/"

  # Create the cron job line dynamically
  cron_line="* * * * * $php_path ${script_dir}run.php"

  # Check if the cron job line already exists in the user's crontab
  if (crontab -l 2>/dev/null | grep -Fxq "$cron_line"); then
    echo "Cron job already exists:"
    echo "$cron_line"
  else
    # Add the cron job line to the user's crontab
    (crontab -l 2>/dev/null; echo "$cron_line") | sudo crontab -
    echo "Cron job added:"
    echo "$cron_line"
  fi
}

# Function to install netstat if not found
install_netstat() {
    if ! command -v netstat &> /dev/null
    then
        echo "netstat is not installed, installing it now..."
        if [[ -f /etc/os-release ]]
        then
            echo "Detected OS using /etc/os-release..."
            if grep -qi 'ubuntu' /etc/os-release
            then
                echo "Detected Ubuntu, installing netstat using apt..."
                sudo apt-get update
                sudo apt-get install -y net-tools
            elif grep -qi 'centos' /etc/os-release
            then
                echo "Detected CentOS, installing netstat using yum..."
                sudo yum install -y net-tools
            fi
        fi
    fi
}

# Function to modify sshd settings
modify_sshd() {
    # Change SSH port to 443
    if ! grep -q 'Port 443' /etc/ssh/sshd_config
    then
        echo "SSH port is not 443, changing it now..."
        sudo sed -i.bak 's/#Port 22/Port 443/g' /etc/ssh/sshd_config
    fi

    # Set UsePAM to yes
    if ! grep -q 'UsePAM yes' /etc/ssh/sshd_config
    then
        echo "UsePAM is not set to yes, changing it now..."
        sudo sed -i.bak 's/#UsePAM no/UsePAM yes/g' /etc/ssh/sshd_config
    fi

    # Set TCPKeepAlive to no
    if ! grep -q 'TCPKeepAlive no' /etc/ssh/sshd_config
    then
        echo "TCPKeepAlive is not set to no, changing it now..."
        sudo sed -i.bak 's/#TCPKeepAlive yes/TCPKeepAlive no/g' /etc/ssh/sshd_config
    fi

    # Set ClientAliveInterval to 1
    if ! grep -q 'ClientAliveInterval 1' /etc/ssh/sshd_config
    then
        echo "ClientAliveInterval 1 does not exist, adding it now..."
        echo 'ClientAliveInterval 1' | sudo tee -a /etc/ssh/sshd_config
    fi

    # Restart SSH service
    sudo systemctl restart ssh
}

# Function to create SingleUser.sh script
create_singleuser_script() {
    if [ ! -f /usr/local/bin/SingleUser.sh ]
    then
        echo "SingleUser.sh does not exist, creating it now..."
        sudo tee /usr/local/bin/SingleUser.sh > /dev/null <<EOF
#!/bin/bash

# Set the maximum allowed concurrent connections
MAX_CONNECTIONS=1

# Get the currently logged-in user from PAM_USER environment variable
CURRENT_USER="\$PAM_USER"

# Check if the current user is root
if [ "\$CURRENT_USER" = "root" ]; then
    # Allow root user to have unlimited concurrent connections
    exit 0
fi

# Get the server IP address dynamically
SERVER_IP=\$(hostname -I | awk '{print \$1}')

# Check if the current user is online using netstat and grep
# Note: We're using grep ":443" instead of ":22" because the SSH port was changed to 443
LIVE_CONNECTIONS=\$(sudo netstat -tnpa | grep 'ESTABLISHED.*sshd' | grep ":443" | grep -w "\$CURRENT_USER" | grep "\$SERVER_IP:443" | wc -l)

# Check if the netstat command was successful
if [ \$? -ne 0 ]; then
    echo "Could not retrieve connection information. Access denied."
    exit 1
fi

# Compare the number of live connections with the maximum allowed connections
if [ "\$LIVE_CONNECTIONS" -gt "\$MAX_CONNECTIONS" ]; then
    # Deny access if the number of live connections exceeds the maximum allowed
    echo "Maximum concurrent connections reached. Access denied."
    exit 1
else
    # Allow access if the number of live connections is within the allowed limit
    exit 0
fi
EOF
        sudo chmod +x /usr/local/bin/SingleUser.sh
    fi
}

# Function to add lines to /etc/pam.d/sshd
add_lines_to_sshd() {
    if ! grep -q 'account required pam_exec.so /usr/local/bin/SingleUser.sh' /etc/pam.d/sshd
    then
        echo "Lines do not exist, adding them now..."
        echo 'account required pam_exec.so /usr/local/bin/SingleUser.sh' | sudo tee -a /etc/pam.d/sshd
    fi

    if ! grep -q 'auth required pam_exec.so /usr/local/bin/SingleUser.sh' /etc/pam.d/sshd
    then
        echo 'auth required pam_exec.so /usr/local/bin/SingleUser.sh' | sudo tee -a /etc/pam.d/sshd
    fi
}

get_required_files() {
	#Download App.php, run.php, and print.php
	SCRIPT_DIR="/home/ubuntu/"
	Main_URL="https://raw.githubusercontent.com/hamidabbaasi/sshLimiter/main/"
	APP_URL="${Main_URL}App.php"    
	RUN_URL="${Main_URL}run.php"    
	PRINT_URL="${Main_URL}print.php"

	echo "Downloading App.php, run.php, and print.php..."
	sudo mkdir -p "$SCRIPT_DIR"
	sudo wget -O "${SCRIPT_DIR}App.php" "$APP_URL" || { echo "Error: Failed to download App.php." && exit 1; }
	sudo wget -O "${SCRIPT_DIR}run.php" "$RUN_URL" || { echo "Error: Failed to download run.php." && exit 1; }
	sudo wget -O "${SCRIPT_DIR}print.php" "$PRINT_URL" || { echo "Error: Failed to download print.php." && exit 1; }
}

# Call the functions
get_required_files

install_php
install_nethogs
add_cron_job

install_netstat
modify_sshd
create_singleuser_script
add_lines_to_sshd
