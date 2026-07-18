# Offline bundle contract (v1)

`New-OfflineBundle.ps1` compiles a committed, clean `DevicePolicy` into a small immutable bundle:

- `device-policy.json` — the authored intent.
- `resolved-policy.json` — backend-specific actions and source Git commit/digest.
- `manifest.json` — SHA-256 integrity records for both files.

The compiler refuses a dirty checkout, refuses to overwrite an existing bundle, and removes an incomplete output folder after a failure. It also refuses a policy whose generated action exceeds the policy's declared change-control ceiling.

This is deliberately an unsigned development format. The next milestone is signing the manifest in the connected build environment, then accepting only trusted signatures on removable media.

Example:

```powershell
.\tools\Test-PolicySchema.ps1 -PolicyPath .\fixtures\policies\packaging-line-hmi.json
.\tools\New-OfflineBundle.ps1 -PolicyPath .\fixtures\policies\packaging-line-hmi.json -OutputPath .\out\packaging-line-hmi-1.0.0
.\tools\Test-OfflineBundle.ps1 -BundlePath .\out\packaging-line-hmi-1.0.0
```
