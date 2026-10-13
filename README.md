<div align="center">
  <img src="img/mithen-logo.png" alt="MithenTool logo" width="128">

  # MithenTool

  [![Releases](https://img.shields.io/github/v/release/catchem88/mithen-tool.svg?label=Release)](https://github.com/catchem88/mithen-tool/releases/latest)
  [![Downloads](https://img.shields.io/github/downloads/catchem88/mithen-tool/total?label=Downloads)](https://github.com/catchem88/mithen-tool/releases)
  [![License](https://img.shields.io/github/license/catchem88/mithen-tool.svg?label=License)](https://github.com/catchem88/mithen-tool/blob/main/LICENSE)
  [![Made with Fluent Design](https://img.shields.io/badge/fluent-design-blue?color=gray&labelColor=0078D7&label=Fluent)](https://github.com/bdlukaa/fluent_ui)

</div>

<br>

A tool to personalize [MithenOS](https://github.com/catchem88/mithen-os) to your needs. Rewritten in Dart with Fluent UI.

## Features

- **AppX manager** - inspect and remove inbox/bloat packages for all users, with deprovisioning so they do not come back.
- **WinSxS removal packages** - install/uninstall the playbook component packages.
- **Microsoft Store apps** - search and install Store apps directly.
- **Tweaks** - performance, security, personalization, updates and utilities toggles.
- **Tools** - one-click launchers for Microsoft Activation Scripts (MAS) and ChrisTitusTech WinUtil in a new elevated PowerShell window, plus a GitHub link for every Mithen app.
- **System Monitor** - shows whether the disabled/removed items are still in the expected state and flags anything that drifted back (for example, an app reinstalled by Windows Update).
- **Cleanup** - finds leftovers of programs whose own uninstaller is already gone (stale Add or remove programs entries, dead Open with and file associations, registry keys, program folders, scheduled tasks, services and startup items) and removes them. Every change is backed up first and can be restored.
- **CLI** - every action is also available from the command line (`mithentool.exe`), which is what the MithenOS playbook uses.

## Requirements

- MithenOS (or ReviOS) installed - this tool is not meant to run on stock Windows and may cause issues if used elsewhere.

## Install

Download `MithenTool-Setup.exe` from the [latest release](https://github.com/catchem88/mithen-tool/releases/latest) and run it. The installer needs administrator rights.

## License

MithenTool is licensed under the [GNU General Public License v3.0](LICENSE).

The tool also contains:
* [Fluent System Icons](https://github.com/microsoft/fluentui-system-icons) by Microsoft - MIT