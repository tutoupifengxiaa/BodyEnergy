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

## Run iPhone and Apple Watch together

1. Select the `Run iOS + Watch` scheme in Xcode.
2. Select `My Mac` as the run destination.
3. Press Run. The launcher boots a paired iPhone and Apple Watch simulator, builds both apps, installs them, and opens both.

The default simulator pair can be overridden with the `BODY_ENERGY_IPHONE_SIMULATOR` and `BODY_ENERGY_WATCH_SIMULATOR` environment variables.
