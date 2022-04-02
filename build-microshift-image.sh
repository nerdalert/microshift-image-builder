#!/bin/bash

set -e -o pipefail

# Constants
EDGE_CONTAINER_BLUEPRINT=microshift-blueprint-v0.0.1.toml
EDGE_INSTALLER_BLUEPRINT=installer.toml
EDGE_CONTAINER_NAME=microshift-build
OSTREE_CONTAINER=microshift-ostree
MICROSHIFT_IMAGE=microshift-installer
BUILD_STATUS_FINISHED="FINISHED"
BUILD_STATUS_FAILED="FAILED"

title() {
  echo -e "\E[34m\n# $1\E[00m"
}

install_deps() {
  sudo dnf -y install  \
    git osbuild-composer composer-cli \
    podman virt-install libvirt
}

open_firewall() {
  sudo firewall-cmd --add-service=cockpit
  sudo firewall-cmd --add-service=cockpit --permanent
  sudo systemctl enable --now osbuild-composer.socket
  sudo systemctl enable --now libvirtd
}

add_repos() {
  sudo mkdir -p /etc/osbuild-composer/repositories/
  sudo cp rhel-85.json /etc/osbuild-composer/repositories/
  sudo cp rhel-8.json /etc/osbuild-composer/repositories/
  sudo composer-cli sources add transmission.toml
  sudo composer-cli sources add microshift.toml
  sudo systemctl restart osbuild-composer.service
}

build_microshift() {
  sudo composer-cli blueprints push "${EDGE_CONTAINER_BLUEPRINT}"
  UUID=$(sudo composer-cli compose start-ostree --ref rhel/8/$(uname -i)/edge "${EDGE_CONTAINER_NAME}" edge-container | awk '{print $2}')
  command="sudo composer-cli compose status"

  title "Waiting for blueprint ${EDGE_CONTAINER_NAME} build to finish building.."
  while [[ $($command | grep "$UUID" | grep "${BUILD_STATUS_FINISHED}" >/dev/null; echo $?) != "0" ]]; do

    if $command | grep "${UUID}" | grep "${BUILD_STATUS_FAILED}" ; then
      echo "Image compose failed while running:"
      echo "sudo composer-cli compose start-ostree --ref rhel/8/$(uname -i)/edge "${EDGE_CONTAINER_NAME}" edge-container"
      exit 1
    else
      echo $($command | grep "${UUID}")
    fi
    sleep 20
  done

  run_container "${UUID}"
}

run_container() {
  title "Starting the ostree tarball pod containing the OSTree commit"
  # Check if an existing OSTree pod is running
  if sudo podman ps -a --format '{{.Names}}' | grep -Eq "^${OSTREE_CONTAINER}\$"; then
      title "Found an existing container named [${OSTREE_CONTAINER}] deleting it in 30 seconds, ctrl^c to exit"
      sleep 10
      title "Found an existing container named [${OSTREE_CONTAINER}] deleting it in 20 seconds, ctrl^c to exit"
      sleep 10
      title "Found an existing container named [${OSTREE_CONTAINER}] deleting it in 10 seconds, ctrl^c to exit"
      sleep 10
      sudo podman rm --force "${OSTREE_CONTAINER}"
  fi

  local UUID=$1
  sudo composer-cli compose image "${UUID}"
  IMAGEID=$(cat "${UUID}"-container.tar | sudo podman load | grep -o -P '(?<=sha256[@:])[a-z0-9]*')
  sudo podman tag "${IMAGEID}" localhost/"${OSTREE_CONTAINER}"
  sudo podman run --rm -d -p 8080:8080 --name "${OSTREE_CONTAINER}" localhost/"${OSTREE_CONTAINER}"
  curl http://localhost:8080/repo/config
}

remove_repos() {
  sudo rm /etc/osbuild-composer/repositories/rhel-8.json
  sudo rm /etc/osbuild-composer/repositories/rhel-85.json
  sudo systemctl restart osbuild-composer.service
}

build_iso() {
    sudo composer-cli blueprints push "${EDGE_INSTALLER_BLUEPRINT}"
    UUID=$(sudo composer-cli compose start-ostree --ref rhel/8/x86_64/edge --url http://localhost:8080/repo/ "${MICROSHIFT_IMAGE}" edge-installer| awk '{print $2}')
    title "Waiting for blueprint "${MICROSHIFT_IMAGE}" build to finish building.."
    command="sudo composer-cli compose status"
    while [[ $($command | grep "$UUID" | grep "${BUILD_STATUS_FINISHED}" >/dev/null; echo $?) != "0" ]]; do
      if $command | grep "${UUID}" | grep "${BUILD_STATUS_FAILED}" ; then
        echo "Image compose failed while running:"
        echo "sudo composer-cli compose start-ostree --ref rhel/8/x86_64/edge --url http://localhost:8080/repo/ "${MICROSHIFT_IMAGE}" edge-installer"
        exit 1
      else
        echo $($command | grep "${UUID}")
      fi
      sleep 20
    done
    sudo composer-cli compose image "${UUID}"
    title "Microshift ISO saved to microshift-installer-${UUID}.iso, moving the image to [ /var/lib/libvirt/images ]"
    sudo mv ${UUID}-installer.iso /var/lib/libvirt/images/microshift-installer-${UUID}.iso
    echo "verify HW virtualization support using [ grep --color vmx /proc/cpuinfo ]"
    title "Build was successful, run the following to start the new image using libvirt:"
    cat <<EOF
sudo virt-install \\
    --name microshift-edge-node \\
    --vcpus 4 \\
    --memory 8192 \\
    --disk path=/var/lib/libvirt/images/microshift-edge.qcow2,size=20 \\
    --network network=default,model=virtio,mac=52:54:00:00:00:$(shuf -i 11-99 -n 1) \\
    --os-type linux \\
    --os-variant rhel8.5 \\
    --location /var/lib/libvirt/images/microshift-installer-${UUID}.iso \\
    --extra-args="ks=file:/kickstart.ks console=ttyS0,115200n8 serial" \\
    --initrd-inject="$(pwd)/kickstart.ks" \\
    --boot uefi
EOF
}

title "Installing dependencies"
install_deps

title "Opening ports for OSbuild and starting services"
open_firewall

title "Adding repos for Microshift blueprint build"
add_repos

title "Building Microshift image, this step will take a few minutes"
build_microshift

title "Removing Image Builder repositories"
remove_repos

title "Build Microshift Edge Installer ISO, this step will take a few minutes"
build_iso
