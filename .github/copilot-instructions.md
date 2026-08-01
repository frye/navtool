# Navtool agent launch rules

- On macOS and Linux, launch the app and capture screenshots only with `./scripts/run.sh`.
- On Windows, launch the app and capture screenshots only with `.\scripts\run.ps1`.
- Never use raw `dotnet run`, `dotnet exec`, or direct `Navtool.App.dll` execution for a functional launch or smoke test.
- Build native artifacts only in the current worktree. Never use a router bridge from another checkout.
- Use `scripts/build-native.sh` or `scripts/build-native.ps1` for native-only validation.
- Use `scripts/publish.sh` or `scripts/publish.ps1` for distributable artifacts.
- Before reporting a successful launch, verify the bridge preflight succeeds and the app does not show `Routing engine unavailable`.
