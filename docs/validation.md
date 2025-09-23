# Toolsmith QCOW2 Validation Guide

This document captures the minimum smoke tests required before publishing a FountainKit Toolsmith image. Run these checks after generating a new QCOW2 with `./build/build-image.sh` and before cutting a release tag.

## Prerequisites

- The QCOW2 image produced by the build script, stored under `dist/`.
- The private SSH key that matches the public key baked into the image via `build/authorized_keys`.
- QEMU (`qemu-system-x86_64`) and `ssh` available on the host machine.

## Quick-start script

The repository provides `scripts/validate.sh` to automate the boot and baseline verification flow. Invoke it with the path to the QCOW2 image:

```bash
./scripts/validate.sh dist/fountainkit-toolsmith-ubuntu-2204-<date>.qcow2
```

The script will:

1. Launch the VM with QEMU, forwarding guest SSH port 22 to host port 2222.
2. Wait for SSH to become available.
3. Execute the smoke tests listed below via SSH.
4. Power off the VM when all checks complete.

You can also perform the steps manually if you prefer.

## Required smoke tests

1. **Boot verification**
   - Confirm the VM reaches the login prompt without errors.
   - Ensure `qemu-guest-agent` starts successfully (`systemctl is-active qemu-guest-agent`).
2. **User and SSH access**
   - SSH into the VM as `fountain` using your private key.
   - Verify passwordless sudo: `sudo whoami` should return `root` without a password prompt.
   - Confirm password authentication is disabled by checking `/etc/ssh/sshd_config`.
3. **Package baseline**
   - Ensure `curl`, `git`, `python3`, and `python3-pip` are installed: `which curl git python3 pip3`.
   - Run `python3 --version` and `pip3 --version` to confirm interpreter availability.
4. **Filesystem health**
   - Check available disk space: `df -h /` should reflect the 20 GiB virtual disk.
   - Inspect `/etc/fountainkit` to confirm the directory exists for future configuration drops.
5. **Guest shutdown**
   - Execute `sudo shutdown now` and confirm the QEMU process exits cleanly.

## Recording results

Capture the console output or SSH session logs for the commands above and attach them to the release PR. Store longer-form validation transcripts under `docs/validation-logs/` if additional context is required.

## Troubleshooting tips

- If SSH never becomes available, connect to the QEMU console and inspect `journalctl -xe` for boot failures.
- When smoke tests fail, do not publish the artifact. Fix the automation under `build/`, rebuild, and re-run this checklist.
