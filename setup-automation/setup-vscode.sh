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
TARBALL_URL="https://github.com/rhpds/zt-network-automation-workshop/archive/refs/heads/main.tar.gz"
echo "Downloading workshop repo tarball..." >> /tmp/progress.log
curl -sL "${TARBALL_URL}" | tar xz -C /tmp >> /tmp/progress.log 2>&1
REPO_DIR="/tmp/zt-network-automation-workshop-main"

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

# ---------------------------------------------------------------------------
# Add ~/.local/bin to PATH for the rhel user.
# ---------------------------------------------------------------------------
if ! grep -q '.local/bin' /home/$USER/.bashrc 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/$USER/.bashrc
  chown $USER:$USER /home/$USER/.bashrc
fi

# ---------------------------------------------------------------------------
# Router SSH access — wrapper scripts so students can type `ssh rtr1` or `rtr1`
# from the VS Code terminal. Routers are reachable via containerlab port forwarding.
# ---------------------------------------------------------------------------
setup_router_access() {
  echo "Setting up router SSH access on vscode VM..." >> /tmp/progress.log

  if ! command -v sshpass &>/dev/null; then
    echo "WARNING: sshpass not available; router SSH wrappers will not work" >> /tmp/progress.log
    return 0
  fi

  for rtr_entry in "rtr1 2222" "rtr2 2223" "rtr3 2225" "rtr4 2226"; do
    local rtr_name="${rtr_entry% *}"
    local rtr_port="${rtr_entry#* }"
    cat > "/usr/local/bin/${rtr_name}" <<WRAPPER
#!/bin/bash
exec sshpass -p 'admin@123' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${rtr_port} admin@containerlab "\$@"
WRAPPER
    chmod 755 "/usr/local/bin/${rtr_name}"
  done

  cat > /etc/profile.d/router-ssh.sh <<'PROFILE'
ssh() {
  case "$1" in
    rtr[1-4])
      local port
      case "$1" in
        rtr1) port=2222 ;; rtr2) port=2223 ;; rtr3) port=2225 ;; rtr4) port=2226 ;;
      esac
      sshpass -p 'admin@123' /usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$port" "admin@containerlab" "${@:2}"
      ;;
    *)
      /usr/bin/ssh "$@"
      ;;
  esac
}
PROFILE
  chmod 644 /etc/profile.d/router-ssh.sh

  echo "Router access configured on vscode — rtr1/rtr2/rtr3/rtr4 via containerlab ports" >> /tmp/progress.log
}
setup_router_access

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

echo "setup-vscode.sh complete" >> /tmp/progress.log
