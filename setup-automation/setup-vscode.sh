#!/bin/bash
USER=rhel

echo "Setup vscode" > /tmp/progress.log
chmod 666 /tmp/progress.log

# ---------------------------------------------------------------------------
# Install code-server (curl pattern from zt-quarkus-intro).
# ---------------------------------------------------------------------------
mkdir -p /home/$USER/.local/share/code-server/User/
mkdir -p /home/$USER/.config/code-server/

cat > /home/$USER/.config/code-server/config.yaml <<EOF
bind-addr: 0.0.0.0:8080
auth: none
cert: false
disable-update-check: true
EOF

cat > /home/$USER/.local/share/code-server/User/settings.json <<EOL
{
  "git.ignoreLegacyWarning": true,
  "window.menuBarVisibility": "visible",
  "git.enableSmartCommit": true,
  "workbench.tips.enabled": false,
  "workbench.startupEditor": "readme",
  "telemetry.enableTelemetry": false,
  "search.smartCase": true,
  "git.confirmSync": false,
  "workbench.colorTheme": "Visual Studio Dark",
  "update.showReleaseNotes": false,
  "update.mode": "none",
  "files.exclude": {
    "**/.*": true
  },
  "security.workspace.trust.enabled": false,
  "redhat.telemetry.enabled": false
}
EOL

# Own the entire .config and .local trees now. The script runs as root and
# creates these dirs, but podman/pip later run as $USER and need write access.
chown -R $USER:$USER /home/$USER/.config /home/$USER/.local

echo "Installing code-server..." >> /tmp/progress.log
curl -fsSL https://code-server.dev/install.sh | sh >> /tmp/progress.log 2>&1
systemctl enable --now code-server@$USER
echo "code-server installed and started on port 8080" >> /tmp/progress.log

# ---------------------------------------------------------------------------
# Sudoers and lingering for rhel user.
# ---------------------------------------------------------------------------
echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
chmod 440 /etc/sudoers.d/rhel_sudoers
loginctl enable-linger $USER 2>/dev/null || true

# Suppress the "Register this system with Red Hat Insights" MOTD.
rm -f /etc/profile.d/insights-client.sh 2>/dev/null
rm -f /etc/motd.d/insights-client 2>/dev/null

# ---------------------------------------------------------------------------
# Register with RHSM so dnf repos are available, then install packages.
# Uses the same REG_USER/REG_PASS env vars as setup-control.sh.
# ---------------------------------------------------------------------------
if [[ -n "${REG_ORG:-}" && -n "${REG_ACTIVATION_KEY:-}" ]]; then
  echo "Registering with subscription-manager (activation key)..." >> /tmp/progress.log
  subscription-manager register --org="$REG_ORG" --activationkey="$REG_ACTIVATION_KEY" \
    --force >> /tmp/progress.log 2>&1 \
    && echo "RHSM registration successful" >> /tmp/progress.log \
    || echo "WARNING: RHSM registration failed" >> /tmp/progress.log
elif [[ -n "${REG_USER:-}" && -n "${REG_PASS:-}" ]]; then
  echo "Registering with subscription-manager (username/password)..." >> /tmp/progress.log
  subscription-manager register --username "$REG_USER" --password "$REG_PASS" \
    --auto-attach --force >> /tmp/progress.log 2>&1 \
    && echo "RHSM registration successful" >> /tmp/progress.log \
    || echo "WARNING: RHSM registration failed" >> /tmp/progress.log
else
  echo "REG_ORG/REG_ACTIVATION_KEY and REG_USER/REG_PASS not set; skipping RHSM registration" >> /tmp/progress.log
fi

subscription-manager repos \
  --enable=rhel-9-for-x86_64-baseos-rpms \
  --enable=rhel-9-for-x86_64-appstream-rpms >> /tmp/progress.log 2>&1 || true

echo "Installing packages via dnf (git, podman, sshpass)..." >> /tmp/progress.log
dnf install -y git podman sshpass python3-pip >> /tmp/progress.log 2>&1 \
  && echo "System packages installed" >> /tmp/progress.log \
  || echo "WARNING: dnf install failed (RHSM may not be registered)" >> /tmp/progress.log

# ---------------------------------------------------------------------------
# Kick off slow background tasks now that podman is available.
# Re-chown in case dnf/podman install created new files under ~rhel.
# ---------------------------------------------------------------------------
chown -R $USER:$USER /home/$USER/.config /home/$USER/.local 2>/dev/null
EE_PULL_PID=""
if command -v podman &>/dev/null; then
  echo "Starting network EE pull in background..." >> /tmp/progress.log
  nohup sudo -u $USER -H podman pull quay.io/acme_corp/network-ee:latest \
    >> /tmp/progress.log 2>&1 &
  EE_PULL_PID=$!
fi

PIP_PID=""
(
  for attempt in 1 2 3; do
    echo "ansible-navigator install attempt ${attempt}..." >> /tmp/progress.log
    if sudo -u $USER -H python3 -m pip install ansible-navigator --user >> /tmp/progress.log 2>&1; then
      echo "ansible-navigator installed" >> /tmp/progress.log
      break
    else
      echo "WARNING: ansible-navigator install attempt ${attempt} failed (exit $?)" >> /tmp/progress.log
      if [[ $attempt -lt 3 ]]; then
        sleep 5
      else
        echo "ERROR: ansible-navigator install failed after 3 attempts" >> /tmp/progress.log
      fi
    fi
  done
) &
PIP_PID=$!

# ---------------------------------------------------------------------------
# Download workshop repo and copy exercise + bundled RPM files.
# ---------------------------------------------------------------------------
TARBALL_URL="https://github.com/andubiel/zt-201-network-automation-workshop/archive/refs/heads/main.tar.gz"
echo "Downloading workshop repo tarball..." >> /tmp/progress.log
curl -sL "${TARBALL_URL}" | tar xz -C /tmp >> /tmp/progress.log 2>&1
REPO_DIR="/tmp/zt-201-network-automation-workshop-main"

if [[ -d "${REPO_DIR}/rpms" ]]; then
  echo "Installing any bundled RPMs..." >> /tmp/progress.log
  for rpm_file in "${REPO_DIR}"/rpms/*.rpm; do
    rpm -Uvh "${rpm_file}" >> /tmp/progress.log 2>&1 || true
  done
fi

# ---------------------------------------------------------------------------
# Copy exercise files to ~rhel/network-workshop.
# ---------------------------------------------------------------------------
if [[ -d "${REPO_DIR}/network-workshop" ]]; then
  cp -r "${REPO_DIR}/network-workshop" /home/$USER/network-workshop
  cp "${REPO_DIR}/network-workshop/.ansible-navigator.yml" /home/$USER/.ansible-navigator.yml
  chown -R $USER:$USER /home/$USER/network-workshop /home/$USER/.ansible-navigator.yml
  echo "Exercise files copied to /home/$USER/network-workshop" >> /tmp/progress.log
else
  echo "WARNING: network-workshop directory not found in repo" >> /tmp/progress.log
fi

# Remove network-workshop directory as we'll use the GitLab workshop content instead
echo "Removing network-workshop directory (will use GitLab workshop instead)..." >> /tmp/progress.log
if [[ -d "/home/$USER/network-workshop" ]]; then
  sudo -u $USER rm -rf /home/$USER/network-workshop
  echo "network-workshop directory removed" >> /tmp/progress.log
fi

# ---------------------------------------------------------------------------
# Add ~/.local/bin to PATH for the rhel user.
# ---------------------------------------------------------------------------
if ! grep -q '.local/bin' /home/$USER/.bashrc 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/$USER/.bashrc
  chown $USER:$USER /home/$USER/.bashrc
fi

# ---------------------------------------------------------------------------
# Switch SSH access — wrapper scripts so students can type `ssh leaf1` or `leaf1`
# from the VS Code terminal. Switches are reachable via containerlab hostname.
# ---------------------------------------------------------------------------
setup_switch_access() {
  echo "Setting up switch SSH access on vscode VM..." >> /tmp/progress.log

  if ! command -v sshpass &>/dev/null; then
    echo "WARNING: sshpass not available; switch SSH wrappers will not work" >> /tmp/progress.log
    return 0
  fi

  # Wrapper scripts: just type `leaf1` or `spine1` to connect passwordlessly.
  for switch in leaf1 leaf2 leaf3 leaf4 spine1 spine2; do
    cat > "/usr/local/bin/${switch}" <<WRAPPER
#!/bin/bash
exec sshpass -p 'admin@123' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@${switch} "\$@"
WRAPPER
    chmod 755 "/usr/local/bin/${switch}"
  done

  # Shell function so `ssh leaf1` also works passwordlessly (all users).
  cat > /etc/profile.d/switch-ssh.sh <<'PROFILE'
ssh() {
  case "$1" in
    leaf[1-4]|spine[1-2])
      sshpass -p 'admin@123' /usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "admin@$1" "${@:2}"
      ;;
    *)
      /usr/bin/ssh "$@"
      ;;
  esac
}
PROFILE
  chmod 644 /etc/profile.d/switch-ssh.sh

  echo "Switch access configured on vscode — leaf1-4, spine1-2 (passwordless)" >> /tmp/progress.log
}
setup_switch_access

# ---------------------------------------------------------------------------
# Wait for background tasks to finish.
# ---------------------------------------------------------------------------
if [[ -n "$PIP_PID" ]]; then
  echo "Waiting for pip/ansible-navigator install (pid $PIP_PID)..." >> /tmp/progress.log
  wait $PIP_PID 2>/dev/null
fi
if [[ -n "$EE_PULL_PID" ]]; then
  echo "Waiting for EE pull (pid $EE_PULL_PID)..." >> /tmp/progress.log
  wait $EE_PULL_PID 2>/dev/null \
    && echo "Network EE pulled" >> /tmp/progress.log \
    || echo "WARNING: Network EE pull failed" >> /tmp/progress.log
fi

# ---------------------------------------------------------------------------
# Final ownership fix — ensure everything under ~rhel is owned by rhel.
# The script runs as root and may have created dirs before chowning.
# ---------------------------------------------------------------------------
chown -R $USER:$USER /home/$USER/.config /home/$USER/.local 2>/dev/null

# ---------------------------------------------------------------------------
# Clone workshop repository from Gitea (on containerlab VM) to VS Code VM
# ---------------------------------------------------------------------------
echo "Setting up workshop repository on VS Code VM..." >> /tmp/progress.log

# Variables
GITEA_USER="gitea"
GITEA_REPO="201-multi-vendor-vxlan-workshop"
GITEA_PASSWORD="gitea123"
BASE_DIR="/home/${USER}"
WORKSHOP_DIR="${BASE_DIR}/${GITEA_REPO}"
GITEA_HOST="containerlab"
GITEA_PORT="8181"
GITEA_URL="http://${GITEA_USER}:${GITEA_PASSWORD}@${GITEA_HOST}:${GITEA_PORT}/${GITEA_USER}/${GITEA_REPO}.git"

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
  sudo -u ${USER} rm -rf "${WORKSHOP_DIR}"
fi

# Clone the upstream workshop content from GitLab
GITLAB_REPO="https://gitlab.com/redhatautomation/201-multi-vendor-vxlan-workshop.git"
DOWNLOAD_DIR="${BASE_DIR}/201-multi-vendor-vxlan-workshop.downloaded"

echo "Cloning upstream workshop from GitLab..." >> /tmp/progress.log
sudo -u ${USER} git clone "${GITLAB_REPO}" "${DOWNLOAD_DIR}" >> /tmp/progress.log 2>&1

if [[ $? -eq 0 ]]; then
  echo "Upstream workshop cloned successfully" >> /tmp/progress.log

  # Remove .git directory from downloaded content
  echo "Removing .git from downloaded content..." >> /tmp/progress.log
  sudo -u ${USER} rm -rf "${DOWNLOAD_DIR}/.git"

  # Clone the empty Gitea repository
  echo "Cloning empty repository from Gitea..." >> /tmp/progress.log
  sudo -u ${USER} git clone "${GITEA_URL}" "${WORKSHOP_DIR}" >> /tmp/progress.log 2>&1

  if [[ $? -eq 0 ]]; then
    echo "Gitea repository cloned successfully" >> /tmp/progress.log

    # Clean Gitea repo (remove everything except .git directory)
    echo "Cleaning Gitea repository (keeping .git)..." >> /tmp/progress.log
    sudo -u ${USER} bash -c "
      cd ${WORKSHOP_DIR}
      find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
    " >> /tmp/progress.log 2>&1

    # Copy content from downloaded to Gitea repo
    echo "Copying workshop content to Gitea repository..." >> /tmp/progress.log
    sudo -u ${USER} bash -c "
      cp -r ${DOWNLOAD_DIR}/* ${WORKSHOP_DIR}/ 2>/dev/null || true
      cp -r ${DOWNLOAD_DIR}/.[^.]* ${WORKSHOP_DIR}/ 2>/dev/null || true
    " >> /tmp/progress.log 2>&1

    # Set proper ownership
    chown -R ${USER}:${USER} "${WORKSHOP_DIR}"

    # Configure git, commit and push to Gitea
    echo "Committing and pushing to Gitea..." >> /tmp/progress.log
    sudo -u ${USER} bash -c "
      cd ${WORKSHOP_DIR}
      git config user.email '${USER}@local.host'
      git config user.name '${USER}'
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
    sudo -u ${USER} rm -rf "${DOWNLOAD_DIR}"

  else
    echo "WARNING: Failed to clone Gitea repository" >> /tmp/progress.log
  fi
else
  echo "WARNING: Failed to clone upstream workshop from GitLab" >> /tmp/progress.log
  echo "Attempting to clone directly from Gitea..." >> /tmp/progress.log

  # Fallback: try to clone from Gitea directly
  sudo -u ${USER} git clone "${GITEA_URL}" "${WORKSHOP_DIR}" >> /tmp/progress.log 2>&1

  if [[ $? -eq 0 ]]; then
    echo "Workshop repository cloned from Gitea" >> /tmp/progress.log
    chown -R ${USER}:${USER} "${WORKSHOP_DIR}"
  fi
fi

# Create a convenience symlink
if [[ -d "${WORKSHOP_DIR}" ]]; then
  LINK_PATH="${BASE_DIR}/workshop"
  if [[ ! -L "${LINK_PATH}" ]]; then
    sudo -u ${USER} ln -s "${WORKSHOP_DIR}" "${LINK_PATH}" 2>/dev/null || true
    echo "Created symlink: ${LINK_PATH} -> ${WORKSHOP_DIR}" >> /tmp/progress.log
  fi
fi

echo "=== VS Code Gitea setup complete ===" >> /tmp/progress.log
echo "Workshop repository location: ${WORKSHOP_DIR}" >> /tmp/progress.log
echo "Gitea source: http://${GITEA_HOST}:${GITEA_PORT}/${GITEA_USER}/${GITEA_REPO}" >> /tmp/progress.log

echo "setup-vscode.sh complete" >> /tmp/progress.log
