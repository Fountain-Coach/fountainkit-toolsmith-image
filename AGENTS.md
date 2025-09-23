# FountainKit Toolsmith Image Repository Guidelines

## Scope
This guidance applies to every file in the image repository that Fountain Coach maintains for Toolsmith-compatible QCOW2 builds.

## Repository purpose
- Own the entire lifecycle of the FountainKit VM image used by Toolsmith: build, validate, publish, distribute, and document.
- Treat this repository as the canonical home for both the automation _and_ the published QCOW2 bits. Store automation, manifests, and documentation in the tree, and ship the actual QCOW2 via versioned GitHub Release assets attached to tags in this repo.
- Keep the release assets authoritative: every published QCOW2 (the "true physics" of the image) must originate from the automation in this repository and be traceable back to its tag, checksum, and release notes.

## Build and maintenance checklist
1. **Automation first** – Define the image using reproducible tooling (Packer, Ansible, Nix, or shell scripts). Store the automation in `build/`.
2. **Base image** – Start from the same distribution and version FountainKit sandboxes use to keep behaviour aligned between host and VM tooling.
3. **Provisioning** – Reuse FountainKit provisioning scripts. Add new dependencies via automation, not manual guest edits.
4. **Hardening** – Disable unnecessary services, configure SSH keys for Toolsmith's command channel, and ensure the default user matches FountainKit conventions.
5. **Validation** – After building, boot the image locally with QEMU and run the FountainKit integration smoke tests. Document the process in `docs/validation.md`.
6. **Checksum** – Compute the SHA-256 of the final QCOW2 (`shasum -a 256 <file>`) and record it in `manifests/tools.json`.
7. **Release** – Cut a Git tag (for example `vYYYY.MM.DD`) and attach the built QCOW2 (optionally compressed) as a GitHub Release asset. Include checksum files (`.sha256`) and metadata in the release notes so consumers can validate the download.
8. **Manifest update** – Update FountainKit's Toolsmith manifest (`.toolsmith/tools.json`) with the new release asset URL and checksum whenever a release is cut.
9. **Cache hygiene** – Communicate that users must clear `.toolsmith/cache/<image>/<old_digest>/` if they need to force hydration of the new build.
10. **Traceability** – Update `releases/` metadata in this repo (e.g., JSON or markdown entries) so each GitHub Release asset links back to its build inputs, checksum, and Toolsmith manifest fragment.

## Pull request expectations
- Include `build/` automation changes, updated `docs/`, and regenerated manifests together in one PR when rolling an image.
- Provide the SHA-256 and download URL in the PR description, along with validation logs.
- Run the documented validation command suite before requesting review.

## Repository hygiene
- Keep `.gitignore` aligned with large binary patterns (`*.qcow2`, `*.img`, etc.) to prevent accidental commits.
- Use semantic version tags (`vYYYY.MM.DD` or similar) that match the Toolsmith manifest's `version` field.
- Update `README.md` whenever the base distribution or provisioning strategy changes.

