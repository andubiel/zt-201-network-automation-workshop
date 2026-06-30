#!/bin/bash
# Clone workshop repository from Gitea (on containerlab VM) to VS Code VM
# Runs after setup-vscode.sh completes

echo "Setting up workshop repository on VS Code VM..." >> /tmp/progress.log

# Variables
USER="gitea"
REPO="201-multi-vendor-vxlan-workshop"
PASSWORD="gitea123"
RHEL_USER="rhel"
BASE_DIR="/home/${RHEL_USER}"
WORKSHOP_DIR="${BASE_DIR}/${REPO}"
GITEA_HOST="containerlab"
GITEA_PORT="8181"
GITEA_URL="http://${USER}:${PASSWORD}@${GITEA_HOST}:${GITEA_PORT}/${USER}/${REPO}.git"

# Wait for Gitea to be available on containerlab
echo "Waiting for Gitea to be available at ${GITEA_HOST}:${GITEA_PORT}..." >> /tmp/progress.log
for i in {1..30}; do
  if curl -s -f "http://${GITEA_HOST}:${GITEA_PORT}" > /dev/null 2>&1; then
    echo "Gitea is reachable" >> /tmp/progress.log
    break
  fi
  echo "Waiting for Gitea... (attempt $i/30)" >> /tmp/progress.log
  sleep 2
done

# Remove existing workshop directory if it exists
if [[ -d "${WORKSHOP_DIR}" ]]; then
  echo "Removing existing workshop directory..." >> /tmp/progress.log
  sudo -u ${RHEL_USER} rm -rf "${WORKSHOP_DIR}"
fi

# Clone the upstream workshop content from GitLab
GITLAB_REPO="https://gitlab.com/redhatautomation/201-multi-vendor-vxlan-workshop.git"
DOWNLOAD_DIR="${BASE_DIR}/201-multi-vendor-vxlan-workshop.downloaded"

echo "Cloning upstream workshop from GitLab..." >> /tmp/progress.log
sudo -u ${RHEL_USER} git clone "${GITLAB_REPO}" "${DOWNLOAD_DIR}" >> /tmp/progress.log 2>&1

if [[ $? -eq 0 ]]; then
  echo "Upstream workshop cloned successfully" >> /tmp/progress.log

  # Remove .git directory from downloaded content
  echo "Removing .git from downloaded content..." >> /tmp/progress.log
  sudo -u ${RHEL_USER} rm -rf "${DOWNLOAD_DIR}/.git"

  # Clone the empty Gitea repository
  echo "Cloning empty repository from Gitea..." >> /tmp/progress.log
  sudo -u ${RHEL_USER} git clone "${GITEA_URL}" "${WORKSHOP_DIR}" >> /tmp/progress.log 2>&1

  if [[ $? -eq 0 ]]; then
    echo "Gitea repository cloned successfully" >> /tmp/progress.log

    # Copy content from downloaded to Gitea repo
    echo "Copying workshop content to Gitea repository..." >> /tmp/progress.log
    sudo -u ${RHEL_USER} bash -c "
      cp -r ${DOWNLOAD_DIR}/* ${WORKSHOP_DIR}/ 2>/dev/null || true
      cp -r ${DOWNLOAD_DIR}/.[^.]* ${WORKSHOP_DIR}/ 2>/dev/null || true
    " >> /tmp/progress.log 2>&1

    # Set proper ownership
    chown -R ${RHEL_USER}:${RHEL_USER} "${WORKSHOP_DIR}"

    # Configure git, commit and push to Gitea
    echo "Committing and pushing to Gitea..." >> /tmp/progress.log
    sudo -u ${RHEL_USER} bash -c "
      cd ${WORKSHOP_DIR}
      git config user.email '${RHEL_USER}@local.host'
      git config user.name '${RHEL_USER}'
      git add .
      git commit -m 'Initial workshop content from GitLab' || true
      git push origin main || git push origin master || true
    " >> /tmp/progress.log 2>&1

    if [[ $? -eq 0 ]]; then
      echo "Workshop content pushed to Gitea successfully" >> /tmp/progress.log
    else
      echo "WARNING: Failed to push to Gitea" >> /tmp/progress.log
    fi

    # Cleanup downloaded directory
    echo "Cleaning up downloaded content..." >> /tmp/progress.log
    sudo -u ${RHEL_USER} rm -rf "${DOWNLOAD_DIR}"

  else
    echo "WARNING: Failed to clone Gitea repository" >> /tmp/progress.log
  fi
else
  echo "WARNING: Failed to clone upstream workshop from GitLab" >> /tmp/progress.log
  echo "Attempting to clone directly from Gitea..." >> /tmp/progress.log

  # Fallback: try to clone from Gitea directly
  sudo -u ${RHEL_USER} git clone "${GITEA_URL}" "${WORKSHOP_DIR}" >> /tmp/progress.log 2>&1

  if [[ $? -eq 0 ]]; then
    echo "Workshop repository cloned from Gitea" >> /tmp/progress.log
    chown -R ${RHEL_USER}:${RHEL_USER} "${WORKSHOP_DIR}"
  fi
fi

# Create a convenience symlink
if [[ -d "${WORKSHOP_DIR}" ]]; then
  LINK_PATH="${BASE_DIR}/workshop"
  if [[ ! -L "${LINK_PATH}" ]]; then
    sudo -u ${RHEL_USER} ln -s "${WORKSHOP_DIR}" "${LINK_PATH}" 2>/dev/null || true
    echo "Created symlink: ${LINK_PATH} -> ${WORKSHOP_DIR}" >> /tmp/progress.log
  fi
fi

echo "=== VS Code Gitea setup complete ===" >> /tmp/progress.log
echo "Workshop repository location: ${WORKSHOP_DIR}" >> /tmp/progress.log
echo "Gitea source: http://${GITEA_HOST}:${GITEA_PORT}/${USER}/${REPO}" >> /tmp/progress.log