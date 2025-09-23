# Release metadata

Create a new file named after the release tag (for example `v2024.04.30.md`) whenever you publish a Toolsmith image. Include:

- A summary of changes from the previous release.
- The exact `sha256sum` output for the QCOW2 asset.
- A link to the GitHub Release and the uploaded artifact.
- References to validation logs captured under `docs/validation-logs/` if applicable.

These records keep the QCOW2 artifacts traceable back to the automation and validation evidence in this repository.
