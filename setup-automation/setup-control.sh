#!/bin/bash
USER=rhel
EE_IMAGE="registry.redhat.io/ansible-automation-platform-26/ee-supported-rhel9:latest"
NETWORK_EE_IMAGE="quay.io/acme_corp/network-ee"
REPO_URL="https://github.com/rhpds/zt-network-automation-workshop.git"
REPO_DIR="/home/rhel/zt-network-automation-workshop"
RHEL_SSH="/home/rhel/.ssh"

echo "Adding wheel" > /root/post-run.log
usermod -aG wheel rhel

echo "Setup vm control" > /tmp/progress.log
chmod 666 /tmp/progress.log

# ---------------------------------------------------------------------------
# 1. Registry login.
# ---------------------------------------------------------------------------
registry_login() {
  if [[ -n "${REG_USER:-}" && -n "${REG_PASS:-}" ]]; then
    echo "Logging in to registry.redhat.io as ${REG_USER} (root + rhel)..." >> /tmp/progress.log
    podman login registry.redhat.io -u "$REG_USER" -p "$REG_PASS" >> /tmp/progress.log 2>&1 || true
    sudo -u rhel -H podman login registry.redhat.io -u "$REG_USER" -p "$REG_PASS" >> /tmp/progress.log 2>&1
    if [[ $? -eq 0 ]]; then
      echo "Registry login successful" >> /tmp/progress.log
    else
      echo "Registry login failed" >> /tmp/progress.log
    fi
  else
    echo "REG_USER/REG_PASS not set; skipping registry login" >> /tmp/progress.log
  fi
}

# ---------------------------------------------------------------------------
# 2. Pull EE images (each in its own background job).
# ---------------------------------------------------------------------------
pull_ee_image() {
  echo "Pulling EE image ${EE_IMAGE}..." >> /tmp/progress.log
  sudo -u rhel -H podman pull "${EE_IMAGE}" >> /tmp/progress.log 2>&1 \
    && echo "EE image pulled" >> /tmp/progress.log \
    || echo "WARNING: EE pull failed" >> /tmp/progress.log
}

pull_network_ee() {
  echo "Pulling Network EE image ${NETWORK_EE_IMAGE}..." >> /tmp/progress.log
  sudo -u rhel -H podman pull "${NETWORK_EE_IMAGE}" >> /tmp/progress.log 2>&1 \
    && echo "Network EE pulled" >> /tmp/progress.log \
    || echo "WARNING: Network EE pull failed" >> /tmp/progress.log
}

# ---------------------------------------------------------------------------
# 3. Clone the workshop repo.
# ---------------------------------------------------------------------------
clone_repo() {
  if [[ -f "${REPO_DIR}/lab-automation/playbooks/site.yml" ]]; then
    echo "Workshop repo already present at ${REPO_DIR}" >> /tmp/progress.log
    return 0
  fi
  echo "Cloning ${REPO_URL} to ${REPO_DIR}..." >> /tmp/progress.log
  sudo -u rhel -H git clone "${REPO_URL}" "${REPO_DIR}" >> /tmp/progress.log 2>&1
  if [[ $? -eq 0 ]]; then
    echo "Repo cloned successfully" >> /tmp/progress.log
  else
    echo "ERROR: git clone failed" >> /tmp/progress.log
  fi
}

# ---------------------------------------------------------------------------
# 4. Install bundled RPMs.
# ---------------------------------------------------------------------------
install_rpms() {
  local rpm_dir="${REPO_DIR}/rpms"
  if [[ -d "${rpm_dir}" ]]; then
    echo "Installing bundled RPMs from ${rpm_dir}..." >> /tmp/progress.log
    rpm -ivh "${rpm_dir}"/*.rpm >> /tmp/progress.log 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# 5. Wait for SSH key from containerlab, then run lab-automation.
# ---------------------------------------------------------------------------
wait_for_ssh_key() {
  if [[ -f "${RHEL_SSH}/config" ]] && ls "${RHEL_SSH}"/*.pem &>/dev/null 2>&1; then
    echo "SSH key already present on control" >> /tmp/progress.log
    return 0
  fi
  echo "Waiting for SSH key from containerlab..." >> /tmp/progress.log
  for (( i=1; i<=120; i++ )); do
    if ls "${RHEL_SSH}"/*.pem &>/dev/null 2>&1; then
      echo "SSH key arrived after ${i} checks" >> /tmp/progress.log
      return 0
    fi
    sleep 5
  done
  echo "WARNING: SSH key never arrived (~10 min). Containerlab playbooks will fail." >> /tmp/progress.log
}

run_lab_automation() {
  local la_dir="${REPO_DIR}/lab-automation"
  if [[ ! -f "${la_dir}/playbooks/site.yml" ]]; then
    echo "lab-automation/playbooks/site.yml not found; skipping" >> /tmp/progress.log
    return 0
  fi
  echo "Running lab-automation via EE..." >> /tmp/progress.log
  sudo -u rhel -H podman run --rm \
    --network host \
    -v "${la_dir}:/runner/project:Z" \
    -v "/home/rhel/.ssh:/home/runner/.ssh:Z" \
    -e CONTROLLER_PASSWORD="${CONTROLLER_PASSWORD:-}" \
    -e GATEWAY_HOSTNAME="${GATEWAY_HOSTNAME:-}" \
    -e GATEWAY_USERNAME="${GATEWAY_USERNAME:-}" \
    -e GATEWAY_PASSWORD="${GATEWAY_PASSWORD:-}" \
    -e GUID="${GUID:-}" \
    -e DOMAIN="${DOMAIN:-}" \
    "${EE_IMAGE}" \
    ansible-playbook \
      -i /runner/project/inventory/lab.yml \
      /runner/project/playbooks/site.yml \
    >> /tmp/lab-automation-site.log 2>&1 \
  || echo "lab-automation failed; see /tmp/lab-automation-site.log" >> /tmp/progress.log
}

# ---------------------------------------------------------------------------
# Run with parallelism where possible. All background jobs must finish
# before run_lab_automation which needs the EE, repo, and SSH key.
# ---------------------------------------------------------------------------
registry_login

# Start both EE pulls in parallel.
pull_ee_image &
EE_PID=$!
pull_network_ee &
NET_EE_PID=$!

# Clone + RPMs can run while images pull.
clone_repo
install_rpms

# Wait for SSH key (polls every 5s). This usually takes longer than
# the EE pulls, so the images will be ready by the time the key arrives.
wait_for_ssh_key

# Ensure both pulls finished before running lab automation.
echo "Waiting for EE image pulls to finish..." >> /tmp/progress.log
wait $EE_PID 2>/dev/null
wait $NET_EE_PID 2>/dev/null

run_lab_automation

echo "setup-control.sh complete" >> /tmp/progress.log
