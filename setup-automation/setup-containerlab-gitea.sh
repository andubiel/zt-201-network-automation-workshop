#!/bin/bash
# Install and configure Gitea on the containerlab VM
# Runs after setup-containerlab.sh completes

echo "Setting up Gitea on containerlab VM..." >> /tmp/progress.log

# Variables
USER="gitea"
REPO="zt-201-network-automation-workshop"
PASSWORD="gitea123"
RHEL_USER="rhel"
BASE_DIR="/home/${RHEL_USER}"
GITEA_DATA_DIR="${BASE_DIR}/gitea_data"
WORKSHOP_DIR="${BASE_DIR}/${REPO}"
GITEA_URL="http://containerlab:8181"

# Ensure rhel user is in docker group
if ! groups rhel | grep -q docker; then
  echo "Adding rhel user to docker group..." >> /tmp/progress.log
  usermod -aG docker rhel
fi

# Create Gitea data directory
mkdir -p "${GITEA_DATA_DIR}"
chown -R rhel:rhel "${GITEA_DATA_DIR}"
echo "Created Gitea data directory: ${GITEA_DATA_DIR}" >> /tmp/progress.log

# Stop and remove existing Gitea container if it exists
if docker ps -a | grep -q gitea; then
  echo "Removing existing Gitea container..." >> /tmp/progress.log
  docker stop gitea 2>/dev/null || true
  docker rm gitea 2>/dev/null || true
fi

# Deploy Gitea container
echo "Deploying Gitea container..." >> /tmp/progress.log
docker run -d \
  --name gitea \
  --restart always \
  -p 8181:3000 \
  -p 2229:22 \
  -e USER_UID=1000 \
  -e USER_GID=1000 \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__security__INSTALL_LOCK=true \
  -v "${GITEA_DATA_DIR}:/data:z" \
  docker.io/gitea/gitea:latest >> /tmp/progress.log 2>&1

if [[ $? -eq 0 ]]; then
  echo "Gitea container started successfully" >> /tmp/progress.log
else
  echo "ERROR: Failed to start Gitea container" >> /tmp/progress.log
  exit 1
fi

# Wait for Gitea to be ready
echo "Waiting for Gitea to initialize..." >> /tmp/progress.log
for i in {1..30}; do
  if curl -s "${GITEA_URL}" > /dev/null 2>&1; then
    echo "Gitea is ready" >> /tmp/progress.log
    break
  fi
  sleep 2
done

# Create Gitea admin user
echo "Creating Gitea admin user..." >> /tmp/progress.log
docker exec -u git gitea gitea admin user create \
  --username "${USER}" \
  --password "${PASSWORD}" \
  --email "gitea@local.host" \
  --admin >> /tmp/progress.log 2>&1 || echo "User may already exist" >> /tmp/progress.log

# Create repository via API
echo "Creating repository via Gitea API..." >> /tmp/progress.log
curl -s -X POST \
  -u "${USER}:${PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${REPO}\",\"private\":false,\"auto_init\":false}" \
  "${GITEA_URL}/api/v1/user/repos" >> /tmp/progress.log 2>&1 || echo "Repo may already exist" >> /tmp/progress.log

# Wait for API to register the new repo
sleep 2

# Clone the workshop repository and push to Gitea
if [[ -d "${WORKSHOP_DIR}" ]]; then
  echo "Workshop directory already exists at ${WORKSHOP_DIR}" >> /tmp/progress.log

  # Configure git and add Gitea remote
  sudo -u ${RHEL_USER} bash -c "
    cd ${WORKSHOP_DIR}
    git config user.email 'gitea@local.host' 2>/dev/null || true
    git config user.name 'gitea' 2>/dev/null || true

    # Add Gitea as a remote if not already added
    if ! git remote | grep -q gitea; then
      git remote add gitea http://${USER}:${PASSWORD}@containerlab:8181/${USER}/${REPO}.git
    fi

    # Push to Gitea
    git push gitea main 2>&1 || git push gitea main --force 2>&1 || true
  " >> /tmp/progress.log 2>&1

  echo "Pushed workshop content to Gitea" >> /tmp/progress.log
else
  echo "WARNING: Workshop directory ${WORKSHOP_DIR} not found, skipping push to Gitea" >> /tmp/progress.log
fi

echo "=== Gitea setup complete ===" >> /tmp/progress.log
echo "Gitea URL: http://containerlab:8181" >> /tmp/progress.log
echo "Username: ${USER}" >> /tmp/progress.log
echo "Repository: ${REPO}" >> /tmp/progress.log
