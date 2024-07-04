#!/bin/bash

export VM_HOSTNAME

echo '> Setting system hostname ...'
hostnamectl set-hostname $VM_HOSTNAME
# sudo systemctl restart NetworkManager

### Done. ###
echo '> Done.'