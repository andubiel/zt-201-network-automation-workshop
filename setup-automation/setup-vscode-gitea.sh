#!/bin/bash
# All-in-One Gitea Deployment Script
# This creates the Compose file, deploys the container, and configures the repos using Docker.

set -e

# Variables
USER="gitea"
REPO="201-multi-vendor-vxlan-workshop"
PASSWORD="gitea123"
RHEL_USER="rhel"
BASE_DIR="/home/${RHEL_USER}"
GITEA_DATA_DIR="${BASE_DIR}/gitea_data"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
WORKSHOP_REMOTE_DIR="${BASE_DIR}/201-multi-vendor-vxlan-workshop-remote"
WORKSHOP_DIR="${BASE_DIR}/201-multi-vendor-vxlan-workshop"
export ANSIBLE_HOST="containerlab"
 
# 1. Clone the remote workshop repository
echo "Cloning remote workshop repository..."
sudo -u ${RHEL_USER} git clone \
  https://gitlab.com/redhatautomation/201-multi-vendor-vxlan-workshop.git \
  ${WORKSHOP_REMOTE_DIR} || true
  
# 2. Cleanup remote and local directory
echo "Cleaning up .git from remote directory..."
sudo -u ${RHEL_USER} rm -rf "${WORKSHOP_REMOTE_DIR}/.git"
sudo -u ${RHEL_USER} rm -rf "${WORKSHOP_DIR}/"



# 3. Clone the local Gitea repository
echo "Cloning local Gitea repository..."
sudo -u ${RHEL_USER} git clone \
  http://${USER}:${PASSWORD}@${ANSIBLE_HOST}:8181/${USER}/${REPO}.git \
  ${WORKSHOP_DIR} || true

# 4. Copy files from remote to local repository
echo "Copying workshop files..."
sudo -u ${RHEL_USER} rsync -a \
  ${WORKSHOP_REMOTE_DIR}/ \
  ${WORKSHOP_DIR}/

# 5. Configure Git and push to Gitea
echo "Configuring Git and pushing to Gitea..."
sudo -u ${RHEL_USER} bash -c "cd ${WORKSHOP_DIR} && \
  git config --global user.email admin@example.com && \
  git config --global user.name gitea && \
  git add . && \
  git commit -m 'Initial workshop sync' || true && \
  git push origin main || git push origin main || true" 
echo "Cleaning up..."
sudo -u ${RHEL_USER} rm -rf ${WORKSHOP_REMOTE_DIR}

echo "=== Gitea setup complete ==="
echo "Access at: http://${ANSIBLE_HOST}:8181"
echo "Username: ${USER}"
echo "Password: ${PASSWORD}"