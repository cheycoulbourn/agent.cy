# Claude & Codex bridge release

The onboarding download button opens the latest published GitHub release. Do not ship that button to creators until the release workflow has completed successfully and both signed archives are attached.

## Required GitHub Actions secrets

### macOS signing and notarization

- `AGENTCY_MAC_CERTIFICATE_P12`: Base64-encoded Developer ID Application certificate and private key exported as a `.p12` file.
- `AGENTCY_MAC_CERTIFICATE_PASSWORD`: Password used when exporting the `.p12` file.
- `AGENTCY_MAC_SIGN_IDENTITY`: Full Developer ID Application identity shown by Keychain Access.
- `AGENTCY_NOTARY_APPLE_ID`: Apple Account used for notarization.
- `AGENTCY_NOTARY_TEAM_ID`: Apple Developer team identifier.
- `AGENTCY_NOTARY_APP_PASSWORD`: App-specific password created for notarization.

### Windows signing

- `AGENTCY_WINDOWS_CERTIFICATE_PFX`: Base64-encoded Windows code-signing certificate and private key exported as a `.pfx` file.
- `AGENTCY_WINDOWS_CERTIFICATE_PASSWORD`: Password used when exporting the `.pfx` file.

## Publish

Run **Package Claude & Codex bridge** from GitHub Actions and enter a version such as `v0.1.0`. The workflow builds both platforms, signs them, notarizes the Mac archive, creates SHA-256 checksums, and publishes a public GitHub release.

After the workflow succeeds, verify:

1. `https://github.com/cheycoulbourn/agent.cy/releases/latest` opens the new release.
2. The release contains `agentcy-macos.zip`, `agentcy-windows.zip`, and `SHA256SUMS.txt`.
3. macOS opens the installer without an unidentified-developer warning.
4. Windows reports a valid publisher signature.
5. Running either installer creates the content-free `bridge-status.json` heartbeat that onboarding detects.
