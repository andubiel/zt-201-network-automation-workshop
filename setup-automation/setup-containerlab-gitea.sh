#!/bin/bash
# All-in-One Gitea Deployment Script

set -e

# Variables
USER="gitea"
REPO="201-multi-vendor-vxlan-workshop"
PASSWORD="gitea123"
RHEL_USER="rhel"
BASE_DIR="/home/${RHEL_USER}"
GITEA_DATA_DIR="${BASE_DIR}/gitea_data"
WORKSHOP_REMOTE_DIR="${BASE_DIR}/201-multi-vendor-vxlan-workshop-remote"
WORKSHOP_DIR="${BASE_DIR}/201-multi-vendor-vxlan-workshop"
export ANSIBLE_HOST="containerlab"

sudo usermod -aG docker rhel
newgrp docker

# Deploy Gitea Container
sudo -u rhel docker run -d \
  --name gitea \
  --restart always \
  -p 8181:3000 \
  -p 2229:22 \
  -e USER_UID=1000 \
  -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__security__INSTALL_LOCK=true \
  -v /home/rhel/gitea_data:/data:z \
  docker.io/gitea/gitea:latest

echo "Waiting for Gitea to initialize..."
sleep 15

echo "Creating Gitea admin user..."
# Added '-u git' to bypass the mustNotRunAsRoot() restriction
sudo -u rhel docker exec -u git gitea gitea admin user create \
  --username "${USER}" \
  --password "${PASSWORD}" \
  --email "gitea@local.host" \
  --admin || true

echo "Creating repository via API..."
curl -s -X POST \
  -u "${USER}:${PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${REPO}\"}" \
  http://127.0.0.1:8181/api/v1/user/repos/ || true

# Wait for API to register the new repo
sleep 2
echo -e "\nSetup complete."
  
  
  Controller

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
 
# 4. Clone the remote workshop repository
echo "Cloning remote workshop repository..."
sudo -u ${RHEL_USER} git clone \
  https://gitlab.com/redhatautomation/201-multi-vendor-vxlan-workshop.git \
  ${WORKSHOP_REMOTE_DIR} || true
  
# 5. Cleanup remote and local directory
echo "Cleaning up .git from remote directory..."
sudo -u ${RHEL_USER} rm -rf "${WORKSHOP_REMOTE_DIR}/.git"
sudo -u ${RHEL_USER} rm -rf "${WORKSHOP_DIR}/"



# 6. Clone the local Gitea repository
echo "Cloning local Gitea repository..."
sudo -u ${RHEL_USER} git clone \
  http://${USER}:${PASSWORD}@${ANSIBLE_HOST}:8181/${USER}/${REPO}.git \
  ${WORKSHOP_DIR} || true

# 7. Copy files from remote to local repository
echo "Copying workshop files..."
sudo -u ${RHEL_USER} rsync -a \
  ${WORKSHOP_REMOTE_DIR}/ \
  ${WORKSHOP_DIR}/

# 8. Configure Git and push to Gitea
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