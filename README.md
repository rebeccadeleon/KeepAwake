# Keep Awake

A menu bar app that stops your Mac and its display from sleeping. Click the
cup icon and choose how long to stay awake.

Requires macOS 13 or later.

## Build

```bash
./build.sh
open dist/KeepAwake.app
```

`build.sh` only builds `dist/KeepAwake.app`. It does not sign or notarize;
the GitHub Actions workflow does that.

| Variable | Purpose | Default |
|---|---|---|
| `BUNDLE_ID` | Bundle identifier | `com.enrev.KeepAwake` |
| `UNIVERSAL=1` | Build for Apple silicon and Intel (needs full Xcode) | Off |

## Sign and notarize with GitHub Actions

`.github/workflows/release.yml` runs on GitHub's `xcode-27` runner when you
push a tag such as `v1.0` (and then publishes a release), or by hand from the
Actions tab. Its steps:

1. Build the app with `build.sh`
2. Sign the app (Developer ID, hardened runtime)
3. Create `KeepAwake.dmg` with a drag-to-Applications layout
4. Sign the dmg
5. Submit the dmg to Apple and record the submission ID
6. Poll Apple, logging the status every 30 seconds
7. Staple the ticket to the dmg and verify it

### Setup

Put the contents of this folder at the root of your repository, change
`BUNDLE_ID` in the workflow, and add these repository secrets
(Settings → Secrets and variables → Actions):

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | Your Developer ID Application certificate, exported from Keychain Access as `.p12` with its private key, then base64-encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you set when exporting the `.p12` |
| `NOTARY_API_KEY_P8_BASE64` | An App Store Connect API key (`AuthKey_XXXX.p8`), base64-encoded |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The issuer ID shown above the key list |

Encode a file and copy it to the clipboard with:

```bash
base64 -i DeveloperID.p12 | pbcopy
base64 -i AuthKey_XXXX.p8 | pbcopy
```

Create the API key at App Store Connect → Users and Access → Integrations →
App Store Connect API (Team Keys). The `.p8` can be downloaded only once.

### If the job stops before Apple answers

The submission ID is on the run's Summary page, as a notice annotation, and in
the log of the "Submit dmg for notarization" step. Check it from any Mac:

```bash
xcrun notarytool info <submission-id> --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
```

Once the status is `Accepted`, download the `KeepAwake-signed-not-stapled`
artifact from the run (it is the exact file Apple received) and staple it:

```bash
xcrun stapler staple KeepAwake.dmg
```

## Files

- `Sources/KeepAwake/KeepAwakeApp.swift`: the menu bar interface
- `Sources/KeepAwake/SleepManager.swift`: the sleep prevention logic
- `Info.plist`: app metadata (`LSUIElement` hides the Dock icon)
- `build.sh`: builds the app
- `.github/workflows/release.yml`: sign, make dmg, notarize, staple
