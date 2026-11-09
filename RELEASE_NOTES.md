# MithenTool v1.1.1

Companion to MithenOS Playbook v1.1.1: the System Monitor now tracks everything the playbook removes, and can put a group back in order with one click.

## System Monitor

- **New "Packages" group** for Windows Feature-on-Demand packages, checked through `Get-WindowsPackage` and fixed with `Remove-WindowsPackage` (wrapper stubs skipped).
- **24 new checks**, 108 in total:
  - Packages: Internet Explorer, LA57, Tablet PC Math, Steps Recorder, handwriting.
  - Apps: Sound Recorder, Wallet, Copilot app, Office push-notification, Dolby Access, Dolby Digital Plus decoder, Intel Management and Security Status.
  - Registry: Windows Copilot, push-to-install, MRT offers, consumer account content, Teams install block, Outlook run block, Edge Copilot sidebar, taskbar size, Start list view, recently added apps.
  - Service `dmwappushservice`, task `ProgramDataUpdater`.
- **Fix all per group** - Apps, Services, Features, Packages, Tasks, Registry and Hosts each get their own button. It only acts on drifted items that can be fixed automatically, so anything already in the expected state is skipped.

## Utilities

- **Open in Terminal (Admin)** - adds or removes "Open in Terminal (Admin)" in the folder right-click menu: it writes the `OpenWTHereAsAdmin` verbs under `HKCR\Directory\shell` and `HKCR\Directory\Background\shell`, launching the installed Windows Terminal elevated from its package path. App execution aliases (`wt.exe`) do not resolve from an elevated process - that is the "Windows cannot find 'wt.exe'" error - so the full path is used, and PowerShell is the fallback when Windows Terminal is not installed. Off by default; Explorer needs a restart.
- **Disable network connectivity in standby** - writes the `f15576e8-98b7-4186-b944-eafa664402d9` power policy (`ACSettingIndex` / `DCSettingIndex` = 0) so Modern Standby stops keeping the adapter connected. Turning it off deletes the policy and returns to the Windows default. MithenOS applies it automatically on laptops only.
- **Fix all per group** in the System Monitor (unchanged, but worth a mention if you missed the last build).

## Adopted from Revision Tool

- **Telemetry removal package** (`telemetry-removal`) added to the winsxs package list.
- **Pause updates** now also sets `NoAutoUpdate=1`; security updates were slipping through with the pause alone. Both are removed on resume.
- **AppX removal**: failures are no longer scheduled for the next boot when `preserveRoaming` is in play, and `0x80073cf1` (package not registered for the user) counts as already removed.
- **AI removal keeps the Windows 11 Explorer ribbon**: feature overrides `58375086`, `63366798`, `58375066`, `61199980` and `40012896` are disabled on install and restored on uninstall. AIFabric removal no longer falls back to the legacy ribbon, and a failed Copilot/AIFabric restore no longer aborts the whole operation.
- **Feature-override API** in `WinRegistryService` (`obfuscateFeatureId`, `disableFeature`, `deleteFeatureOverride`, plus bulk `disableFeatures` / `resetFeatures`).

## Install

Upgrading over an existing install is fine - run `MithenTool-Setup.exe`, or `MithenTool-Setup.exe /S` for a silent install. The playbook downloads this build automatically through `releases/latest/download/MithenTool-Setup.exe`.
