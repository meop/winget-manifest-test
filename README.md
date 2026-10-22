# winget manifest test

Generates the winget manifest that winget-releaser would submit for a release
with both an MSI and a portable zip, without submitting it (`komac update
--dry-run`), then checks it on x64 and ARM64 Windows runners: `winget
validate`, a fresh default install, a fresh `--installer-type portable`
install, and an upgrade from the previous winget version.

Add a package to `winget-test/packages.json` (its installer URLs must be
public, e.g. this repo's `test-assets` release) and push.
