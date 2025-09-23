#!/usr/bin/env bash
set -euo pipefail

# Boot the generated QCOW2 with QEMU and execute the validation smoke tests.

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-qcow2> [ssh-private-key]" >&2
  exit 1
fi

IMAGE_PATH=$1
SSH_KEY=${2:-$HOME/.ssh/id_ed25519}
SSH_PORT=${SSH_PORT:-2222}
SSH_USER=${SSH_USER:-fountain}
QEMU_RAM_MB=${QEMU_RAM_MB:-4096}
QEMU_SMP=${QEMU_SMP:-2}
STATE_DIR=$(mktemp -d)

cleanup() {
  if [[ -n ${QEMU_PID:-} ]]; then
    if kill -0 "${QEMU_PID}" >/dev/null 2>&1; then
      echo "[INFO] Stopping QEMU process ${QEMU_PID}" >&2
      kill "${QEMU_PID}" || true
      wait "${QEMU_PID}" || true
    fi
  fi
  rm -rf "${STATE_DIR}"
}
trap cleanup EXIT

if [[ ! -f "${IMAGE_PATH}" ]]; then
  echo "[ERROR] QCOW2 image '${IMAGE_PATH}' not found" >&2
  exit 1
fi

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "[ERROR] SSH private key '${SSH_KEY}' not found" >&2
  exit 1
fi

QMP_SOCKET="${STATE_DIR}/qmp.sock"

qemu-system-x86_64 \
  -m "${QEMU_RAM_MB}" \
  -smp "${QEMU_SMP}" \
  -machine accel=kvm:tcg \
  -cpu host \
  -drive "file=${IMAGE_PATH},if=virtio,format=qcow2" \
  -net nic,model=virtio \
  -net user,hostfwd=tcp::"${SSH_PORT}"-:22 \
  -nographic \
  -qmp unix:"${QMP_SOCKET}",server,nowait \
  -monitor none \
  -serial mon:stdio &
QEMU_PID=$!

echo "[INFO] Waiting for SSH availability on localhost:${SSH_PORT}" >&2
for i in {1..120}; do
  if ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "${SSH_USER}@localhost" -p "${SSH_PORT}" true 2>/dev/null; then
    READY=1
    break
  fi
  sleep 5
done

if [[ -z ${READY:-} ]]; then
  echo "[ERROR] SSH did not become available in time." >&2
  exit 1
fi

echo "[INFO] Running validation commands" >&2
run_ssh() {
  ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@localhost" -p "${SSH_PORT}" "$@"
}

run_ssh "systemctl is-active qemu-guest-agent"
run_ssh "sudo whoami"
run_ssh "stat /etc/ssh/sshd_config"
run_ssh "grep -i '^PasswordAuthentication no' /etc/ssh/sshd_config"
run_ssh "which curl git python3 pip3"
run_ssh "python3 --version"
run_ssh "pip3 --version"
run_ssh "df -h /"
run_ssh "stat /etc/fountainkit"

echo "[INFO] Shutting down guest" >&2
run_ssh "sudo shutdown now" || true
sleep 10

if kill -0 "${QEMU_PID}" >/dev/null 2>&1; then
  echo "[INFO] Force stopping QEMU after guest shutdown" >&2
  kill "${QEMU_PID}" || true
  wait "${QEMU_PID}" || true
fi

echo "[INFO] Validation complete" >&2
