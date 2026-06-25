#!/bin/bash
# Runs when showroom targets the containerlab VM (bastion / lab node).
# NOTE: Do NOT use set -e — each section must run independently.
echo "Setup containerlab" >> /tmp/progress.log
chmod 666 /tmp/progress.log 2>/dev/null || true

REPO_URL="https://github.com/rhpds/zt-network-automation-workshop.git"
REPO_DIR="/home/rhel/zt-network-automation-workshop"

# ---------------------------------------------------------------------------
# Clone the workshop repo so we have access to bundled RPMs etc.
# ---------------------------------------------------------------------------
clone_repo() {
  if [[ -d "${REPO_DIR}/.git" ]]; then
    echo "Workshop repo already present on containerlab" >> /tmp/progress.log
    return 0
  fi

  echo "Cloning ${REPO_URL} to ${REPO_DIR} on containerlab..." >> /tmp/progress.log
  sudo -u rhel -H git clone "${REPO_URL}" "${REPO_DIR}" >> /tmp/progress.log 2>&1
  if [[ $? -eq 0 ]]; then
    echo "Repo cloned on containerlab" >> /tmp/progress.log
  else
    echo "WARNING: git clone failed on containerlab" >> /tmp/progress.log
  fi
}

# ---------------------------------------------------------------------------
# Push SSH key + config to 'control' so control can SSH back to containerlab.
# Generates a fresh key pair if none is baked into the image.
# Uses sshpass for the push since key-based auth between VMs is not available.
# ---------------------------------------------------------------------------
push_ssh_key_to_control() {
  local key_user="rhel"
  local key_home="/home/${key_user}"
  local ssh_dir="${key_home}/.ssh"
  local password="ansible123!"

  # Ensure rhel password matches cloud-init / Workshop Credential even if userdata did not re-run.
  echo "${key_user}:${password}" | chpasswd
  echo "Ensured ${key_user} password matches workshop default" >> /tmp/progress.log

  mkdir -p "${ssh_dir}"
  chown "${key_user}:${key_user}" "${ssh_dir}"
  chmod 700 "${ssh_dir}"

  local privkey=""
  if [[ -f "${ssh_dir}/containerlab.pem" ]]; then
    privkey="${ssh_dir}/containerlab.pem"
    echo "Using existing containerlab.pem" >> /tmp/progress.log
  else
    for f in "${ssh_dir}"/*.pem "${ssh_dir}/id_rsa" "${ssh_dir}/id_ed25519"; do
      if [[ -f "$f" ]]; then
        privkey="$f"
        echo "Using existing SSH key ${privkey}" >> /tmp/progress.log
        break
      fi
    done
  fi

  if [[ -z "$privkey" ]]; then
    echo "No existing key found; generating containerlab.pem..." >> /tmp/progress.log
    privkey="${ssh_dir}/containerlab.pem"
    sudo -u "${key_user}" ssh-keygen -t ed25519 \
      -f "${privkey}" -N "" -q -C "containerlab-to-control"
    echo "Generated ${privkey}" >> /tmp/progress.log
  fi

  local pubkey=""
  for candidate in "${privkey%.pem}.pub" "${privkey}.pub"; do
    [[ -f "$candidate" ]] && pubkey="$candidate" && break
  done

  if [[ -n "$pubkey" ]]; then
    touch "${ssh_dir}/authorized_keys"
    chown "${key_user}:${key_user}" "${ssh_dir}/authorized_keys"
    chmod 600 "${ssh_dir}/authorized_keys"
    if ! grep -qF "$(cat "${pubkey}")" "${ssh_dir}/authorized_keys" 2>/dev/null; then
      cat "${pubkey}" >> "${ssh_dir}/authorized_keys"
      echo "Added ${pubkey} to authorized_keys" >> /tmp/progress.log
    else
      echo "${pubkey} already in authorized_keys" >> /tmp/progress.log
    fi
  else
    echo "WARNING: no public key found for ${privkey}" >> /tmp/progress.log
  fi

  if ! command -v sshpass &>/dev/null; then
    echo "ERROR: sshpass not available; cannot push key to control" >> /tmp/progress.log
    return 1
  fi

  local keybase
  keybase="$(basename "${privkey}")"
  echo "Pushing SSH key (${privkey}) to control..." >> /tmp/progress.log

  sshpass -p "${password}" ssh -o StrictHostKeyChecking=no \
    -o ConnectTimeout=30 "${key_user}@control" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh" 2>>/tmp/progress.log
  if [[ $? -ne 0 ]]; then
    echo "ERROR: SSH to control failed" >> /tmp/progress.log
    return 1
  fi

  sshpass -p "${password}" scp -o StrictHostKeyChecking=no \
    "${privkey}" "${key_user}@control:${ssh_dir}/${keybase}" 2>>/tmp/progress.log
  if [[ $? -ne 0 ]]; then
    echo "ERROR: SCP private key to control failed" >> /tmp/progress.log
    return 1
  fi

  if [[ -n "$pubkey" ]]; then
    sshpass -p "${password}" scp -o StrictHostKeyChecking=no \
      "${pubkey}" "${key_user}@control:${ssh_dir}/$(basename "${pubkey}")" \
      2>>/tmp/progress.log || true
  fi

  sshpass -p "${password}" ssh -o StrictHostKeyChecking=no \
    "${key_user}@control" bash -s -- "${keybase}" <<'REMOTE'
    chmod 600 ~/.ssh/"$1" 2>/dev/null
    cat > ~/.ssh/config <<EOF
Host *
  IdentityFile ~/.ssh/$1
  StrictHostKeyChecking no
  ConnectTimeout 60
  ConnectionAttempts 10
EOF
    chmod 600 ~/.ssh/config
REMOTE

  echo "SSH key + config pushed to control successfully" >> /tmp/progress.log
}

# ---------------------------------------------------------------------------
# Set up /etc/hosts, SSH config, sshpass, and wrapper scripts so students
# can connect to routers with just `ssh rtr1` or `rtr1`.
# ---------------------------------------------------------------------------
setup_router_access() {
  echo "Setting up router name resolution and SSH config..." >> /tmp/progress.log

  # /etc/hosts — system-wide. Always rewrite the block; the VM image may
  # contain stale containerlab-managed entries that fool a simple grep check.
  sed -i '/rtr[1-4]/d' /etc/hosts 2>/dev/null
  cat >> /etc/hosts <<'HOSTS'
172.20.20.10 rtr1
172.20.20.20 rtr2
172.20.20.30 rtr3
172.20.20.40 rtr4
HOSTS
  echo "Written rtr1-4 to /etc/hosts (172.20.20.x)" >> /tmp/progress.log

  # SSH config for both rhel and lab-user.
  for u in rhel lab-user; do
    local uhome="/home/${u}"
    local ussh="${uhome}/.ssh"
    if id "${u}" &>/dev/null; then
      mkdir -p "${ussh}"
      cat > "${ussh}/config.d-routers" <<'SSHCFG'
Host rtr1
  Hostname 172.20.20.10
  User admin
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host rtr2
  Hostname 172.20.20.20
  User admin
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host rtr3
  Hostname 172.20.20.30
  User admin
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host rtr4
  Hostname 172.20.20.40
  User admin
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
SSHCFG
      # Append Include if main config exists, otherwise create config directly.
      if [[ -f "${ussh}/config" ]]; then
        grep -q "config.d-routers" "${ussh}/config" 2>/dev/null || \
          sed -i '1i Include ~/.ssh/config.d-routers' "${ussh}/config"
      else
        cat > "${ussh}/config" <<'MAINCFG'
Include ~/.ssh/config.d-routers
MAINCFG
      fi
      chmod 600 "${ussh}/config" "${ussh}/config.d-routers" 2>/dev/null
      chown -R "${u}:${u}" "${ussh}" 2>/dev/null || chown -R "${u}:users" "${ussh}" 2>/dev/null
      echo "SSH router config written for ${u}" >> /tmp/progress.log
    fi
  done

  # Install sshpass from bundled RPM.
  if ! command -v sshpass &>/dev/null; then
    local rpm_path="${REPO_DIR}/rpms/sshpass-1.09-4.el9.x86_64.rpm"
    if [[ -f "${rpm_path}" ]]; then
      rpm -ivh "${rpm_path}" >> /tmp/progress.log 2>&1 || true
      echo "sshpass installed from bundled RPM" >> /tmp/progress.log
    else
      echo "WARNING: sshpass RPM not found at ${rpm_path}" >> /tmp/progress.log
    fi
  else
    echo "sshpass already installed" >> /tmp/progress.log
  fi

  # Wrapper scripts: just type `rtr1` to connect passwordlessly.
  for rtr in rtr1 rtr2 rtr3 rtr4; do
    cat > "/usr/local/bin/${rtr}" <<WRAPPER
#!/bin/bash
exec sshpass -p 'admin@123' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@${rtr} "\$@"
WRAPPER
    chmod 755 "/usr/local/bin/${rtr}"
  done

  # Shell function so `ssh rtr1` also works passwordlessly (all users).
  cat > /etc/profile.d/router-ssh.sh <<'PROFILE'
ssh() {
  case "$1" in
    rtr[1-4])
      sshpass -p 'admin@123' /usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "admin@$1" "${@:2}"
      ;;
    *)
      /usr/bin/ssh "$@"
      ;;
  esac
}
PROFILE
  chmod 644 /etc/profile.d/router-ssh.sh

  echo "Router access configured — rtr1/rtr2/rtr3/rtr4 (passwordless)" >> /tmp/progress.log
}

# ---------------------------------------------------------------------------
# Install any other bundled RPMs (grubby etc.).
# ---------------------------------------------------------------------------
install_rpms() {
  local rpm_dir="${REPO_DIR}/rpms"
  if [[ -d "${rpm_dir}" ]]; then
    echo "Installing bundled RPMs on containerlab..." >> /tmp/progress.log
    for rpm_file in "${rpm_dir}"/*.rpm; do
      rpm -Uvh "${rpm_file}" >> /tmp/progress.log 2>&1 || true
    done
  fi
}

# ---------------------------------------------------------------------------
# Containerlab auto-resume: systemd service that re-deploys the last topology
# after the VM is paused and resumed. A state file tracks which topology was
# last deployed so the service doesn't need a hardcoded path.
# ---------------------------------------------------------------------------
install_clab_resume_service() {
  echo "Installing containerlab-resume systemd service..." >> /tmp/progress.log
  mkdir -p /etc/containerlab

  cat > /usr/local/bin/containerlab-resume <<'RESUME'
#!/bin/bash
STATE_FILE="/etc/containerlab/last-topology"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "containerlab-resume: no state file at $STATE_FILE, nothing to do"
  exit 0
fi

TOPO_DIR="$(cat "$STATE_FILE")"
if [[ -z "$TOPO_DIR" || ! -d "$TOPO_DIR" ]]; then
  echo "containerlab-resume: topology dir '$TOPO_DIR' not found, skipping"
  exit 0
fi

echo "containerlab-resume: destroying existing topology in $TOPO_DIR (if any)"
cd "$TOPO_DIR" || exit 1
# Clean slate after pause/resume or hard stop — avoids stale containers (e.g. vEOS)
# conflicting with deploy --reconfigure. destroy may fail if nothing exists; ignore.
containerlab destroy || true
echo "containerlab-resume: re-deploying topology in $TOPO_DIR"
containerlab deploy --reconfigure
RESUME
  chmod 755 /usr/local/bin/containerlab-resume

  cat > /etc/systemd/system/containerlab-resume.service <<'UNIT'
[Unit]
Description=Re-deploy last containerlab topology after resume
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/containerlab-resume
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable containerlab-resume.service >> /tmp/progress.log 2>&1
  echo "containerlab-resume service installed and enabled" >> /tmp/progress.log
}

# ---------------------------------------------------------------------------
# Run each step independently — failures in one must not block the rest.
# install_rpms runs before push_ssh_key_to_control because sshpass is needed.
# ---------------------------------------------------------------------------
# Suppress the "Register this system with Red Hat Insights" MOTD.
rm -f /etc/profile.d/insights-client.sh 2>/dev/null
rm -f /etc/motd.d/insights-client 2>/dev/null

clone_repo
install_rpms
push_ssh_key_to_control || echo "push_ssh_key_to_control failed" >> /tmp/progress.log
setup_router_access || echo "setup_router_access failed" >> /tmp/progress.log
install_clab_resume_service || echo "install_clab_resume_service failed" >> /tmp/progress.log
echo "setup-containerlab.sh complete" >> /tmp/progress.log
