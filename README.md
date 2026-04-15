# BodyEnergy

## Open in Xcode

This repository stores source code and an `XcodeGen` project spec (`project.yml`).
Generate the Xcode project on macOS before opening it.

1. Install XcodeGen (once):
   - `brew install xcodegen`
2. Generate the project in repo root:
   - `xcodegen generate`
3. Open the generated project:
   - `open BodyEnergy.xcodeproj`

## Build Notes

- Enable Signing & Capabilities for the `BodyEnergy` target.
- HealthKit entitlement file is at `BodyEnergy/App/BodyEnergy.entitlements`.
- If your team requires a custom bundle identifier, update `project.yml` and regenerate.
