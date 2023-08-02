#!/bin/bash

# Check if /home/potato/NFC_Tracking exists before changing directory
if [ -d "/home/potato/NFC_Tracking" ]; then
    cd /home/potato/NFC_Tracking
else
    echo "Directory /home/potato/NFC_Tracking does not exist."
    exit 1
fi

# Create logrotate configuration
if [ ! -f "/etc/logrotate.d/read_ultralight" ]; then
    # The file does not exist, create it
    cat << EOF > /etc/logrotate.d/read_ultralight
    /var/log/read_ultralight.log {
        rotate 7
        daily
        compress
        missingok
        notifempty
        minsize 100M
        create 0664 potato root
        postrotate
            /bin/kill -HUP \`cat /var/run/read_ultralight.pid 2>/dev/null\` 2>/dev/null || true
        endscript
    }
    EOF
fi

# Create systemd service file
if [ ! -f "/etc/systemd/system/monitor.service" ]; then
    # The file does not exist, create it
    cat << EOF > /etc/systemd/system/monitor.service
    [Unit]
    Description=Monitor and restart C program

    [Service]
    Type=simple
    ExecStart=/home/potato/NFC_Tracking/monitor.sh
    User=root
    Group=root
    Environment=PATH=/usr/bin:/usr/local/bin
    WorkingDirectory=/home/potato/NFC_Tracking
    PIDFile=/var/run/read_ultralight.pid
    ExecStop=/bin/kill -15 \$MAINPID
    TimeoutSec=90
    Restart=always
    
    [Install]
    WantedBy=multi-user.target
    EOF
fi

# Reload systemd manager configuration
sudo systemctl daemon-reload

# Enable the service
sudo systemctl enable monitor.service
sudo systemctl enable NetworkManager

# Clone the repository if /home/potato/NFC_Tracking does not exist
if [ ! -d "/home/potato/NFC_Tracking" ]; then
    git clone https://github.com/NxFerrara/NFC_Tracking.git /home/potato/NFC_Tracking
fi

# Install packages from requirements.txt if it exists
if [ -f "/home/potato/NFC_Tracking/requirements.txt" ]; then
    packages=$(cat /home/potato/NFC_Tracking/requirements.txt)
    apt-get install -y $packages
fi

sudo sh compile_all.sh
sudo sh update_permissions.sh

# Check if command-line argument is provided
if [ -z "$1" ]
then
  echo "Please provide the driver name as a command-line argument."
  exit 1
fi

driver=$1  # Get driver name from command-line argument

# Update and upgrade the system
sudo apt update
sudo apt upgrade -y

if [ "$driver" = "wn725n" ]
then
  # Check if the TL-WN725N-TP-Link-Debian directory exists
  if [ ! -d "TL-WN725N-TP-Link-Debian" ]; then
    git clone https://github.com/ilnanny/TL-WN725N-TP-Link-Debian.git
  fi
  sudo apt-get -y install build-essential linux-headers-$(uname -r)
  cd TL-WN725N-TP-Link-Debian
  make all
  make install
  insmod 8188eu.ko
elif [ "$driver" = "ac600" ]
then
  # Check if the rtl8812au directory exists
  if [ ! -d "rtl8812au" ]; then
    git clone https://github.com/aircrack-ng/rtl8812au.git++++++++-+
    sudo apt install -y dkms git build-essential libelf-dev
    cd rtl8812au/
    sudo make dkms_install
  fi
else
  echo "Invalid driver name. Please provide either 'wn725n' or 'ac600' as the command-line argument."
  exit 1
fi

