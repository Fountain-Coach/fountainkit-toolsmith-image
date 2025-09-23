#!/usr/bin/env bash
set -euo pipefail

# Build automation for the FountainKit Toolsmith QCOW2 image.
#
# The script downloads the upstream Ubuntu 22.04 cloud image, applies opinionated
# provisioning using libguestfs tooling, and emits a release-ready QCOW2 along
# with a SHA-256 checksum file.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
DIST_DIR="${REPO_ROOT}/dist"
CACHE_DIR="${REPO_ROOT}/tmp"
mkdir -p "${DIST_DIR}" "${CACHE_DIR}"

# Configuration variables (can be overridden via environment variables).
: "${IMAGE_NAME:=fountainkit-toolsmith}"
: "${IMAGE_VERSION:=$(date +%Y.%m.%d)}"
: "${BASE_IMAGE_URL:=https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img}"
: "${BASE_IMAGE_SHA256:=}"
: "${VIRTUAL_SIZE_GB:=20}"
: "${AUTHORIZED_KEYS:=${SCRIPT_DIR}/authorized_keys}"
: "${DEFAULT_USER:=fountain}"
: "${DIST_IMAGE_PATH:=${DIST_DIR}/${IMAGE_NAME}-ubuntu-2204-${IMAGE_VERSION}.qcow2}"
: "${DIST_CHECKSUM_PATH:=${DIST_IMAGE_PATH}.sha256}"

REQUIRED_TOOLS=(
  curl
  qemu-img
  virt-customize
  virt-sysprep
  sha256sum
)

check_dependencies() {
  local missing=()
  for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      missing+=("${tool}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "[ERROR] Missing required tools: ${missing[*]}" >&2
    echo "Install qemu-utils and libguestfs-tools (or distribution equivalents) before running." >&2
    exit 1
  fi
}

fetch_base_image() {
  local base_image_path="${CACHE_DIR}/$(basename "${BASE_IMAGE_URL}")"
  if [[ ! -f "${base_image_path}" ]]; then
    echo "[INFO] Downloading Ubuntu cloud image from ${BASE_IMAGE_URL}" >&2
    curl -L --fail --output "${base_image_path}" "${BASE_IMAGE_URL}"
  else
    echo "[INFO] Reusing cached base image at ${base_image_path}" >&2
  fi

  if [[ -n "${BASE_IMAGE_SHA256}" ]]; then
    echo "[INFO] Verifying base image checksum" >&2
    local actual
    actual=$(sha256sum "${base_image_path}" | awk '{print $1}')
    if [[ "${actual}" != "${BASE_IMAGE_SHA256}" ]]; then
      echo "[ERROR] Base image checksum mismatch" >&2
      echo "       Expected: ${BASE_IMAGE_SHA256}" >&2
      echo "       Actual:   ${actual}" >&2
      exit 1
    fi
  else
    echo "[WARN] BASE_IMAGE_SHA256 not set; skipping checksum verification." >&2
  fi

  printf '%s' "${base_image_path}"
}

prepare_working_image() {
  local base_image_path=$1
  local working_image="${CACHE_DIR}/${IMAGE_NAME}-working.qcow2"
  rm -f "${working_image}"
  echo "[INFO] Creating writable working copy" >&2
  qemu-img convert -O qcow2 "${base_image_path}" "${working_image}"
  qemu-img resize "${working_image}" "${VIRTUAL_SIZE_GB}G"
  printf '%s' "${working_image}"
}

run_customization() {
  local working_image=$1

  if [[ ! -s "${AUTHORIZED_KEYS}" ]]; then
    echo "[ERROR] Authorized keys file '${AUTHORIZED_KEYS}' is empty or missing." >&2
    echo "Create the file or override the AUTHORIZED_KEYS variable before building." >&2
    exit 1
  fi

  echo "[INFO] Customizing guest filesystem" >&2
  virt-customize -a "${working_image}" \
    --update \
    --install "curl,git,python3,python3-pip,qemu-guest-agent,sudo" \
    --run-command "useradd --create-home --shell /bin/bash ${DEFAULT_USER}" \
    --run-command "usermod -aG sudo ${DEFAULT_USER}" \
    --run-command "echo '${DEFAULT_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-${DEFAULT_USER}" \
    --run-command "chmod 0440 /etc/sudoers.d/90-${DEFAULT_USER}" \
    --ssh-inject "${DEFAULT_USER}:file:${AUTHORIZED_KEYS}" \
    --run-command "passwd -l root" \
    --run-command "mkdir -p /etc/fountainkit" \
    --run-command "systemctl enable ssh" \
    --run-command "sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config" \
    --run-command "apt-get clean" \
    --timezone "UTC"

  echo "[INFO] Performing final sysprep" >&2
  virt-sysprep -a "${working_image}" \
    --operations defaults,-ssh-userdir,-ssh-userdir-content \
    --hostname "toolsmith"
}

finalize_artifacts() {
  local working_image=$1
  echo "[INFO] Writing final artifact to ${DIST_IMAGE_PATH}" >&2
  mv "${working_image}" "${DIST_IMAGE_PATH}"
  qemu-img info "${DIST_IMAGE_PATH}" >&2

  echo "[INFO] Generating SHA-256 checksum" >&2
  (cd "${DIST_DIR}" && sha256sum "$(basename "${DIST_IMAGE_PATH}")" > "$(basename "${DIST_CHECKSUM_PATH}")")
}

main() {
  check_dependencies
  local base_image
  base_image=$(fetch_base_image)
  local working_image
  working_image=$(prepare_working_image "${base_image}")
  run_customization "${working_image}"
  finalize_artifacts "${working_image}"
  echo "[INFO] Build complete: ${DIST_IMAGE_PATH}" >&2
  echo "[INFO] Checksum: ${DIST_CHECKSUM_PATH}" >&2
}

main "$@"
