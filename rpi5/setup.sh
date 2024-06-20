#!/usr/bin/env bash
#
# Copyright (c) 2024. Anshul Gupta
# All rights reserved.
#

# This script is used to setup the Raspberry Pi 5

set -eux

# Set the hostname
sudo hostnamectl set-hostname rpi5

# Install avahi
# It doesn't work with pre-made ubuntu image, so we need to install it manually
sudo snap install avahi

# Touch avahi config file
sudo touch /var/snap/avahi/common/etc/avahi/avahi-daemon.conf

# Restart avahi service
sudo snap restart avahi.daemon

# Start microk8s
sudo microk8s start
sudo microk8s status --wait-ready

# Enable microk8s addons
sudo microk8s enable dns
sudo microk8s enable storage
sudo microk8s enable dashboard
sudo microk8s enable cert-manager
sudo microk8s enable community
sudo microk8s enable argocd
sudo microk8s enable ingress:default-ssl-certificate=ingress/default-cert-tls

# Setup mayastor
sudo sysctl vm.nr_hugepages=1024
echo 'vm.nr_hugepages=1024' | sudo tee -a /etc/sysctl.d/local.conf
sudo modprobe nvme_tcp
echo 'nvme-tcp' | sudo tee -a /etc/modules-load.d/microk8s-mayastor.conf

sudo microk8s stop
sudo microk8s start
sudo microk8s status --wait-ready

sudo microk8s enable core/mayastor --default-pool-size 20G
sudo microk8s mayastor-pools add --device /dev/nvme0n1
