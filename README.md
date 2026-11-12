<p align="center">
  <img src="img/mithen-logo.png" alt="MithenTool logo" width="180">
</p>

<h1 align="center">MithenTool</h1>

<div align="center">
MithenTool is a lightweight companion tool for <a href="https://github.com/catchem88/mithen-os">MithenOS</a>: apply, verify and undo the playbook's Windows changes, install the Mithen apps, and clean up after programs that are already gone. A Windows focused fork of the <a href="https://github.com/meetrevision/revision-tool">Revision Tool</a> by the meetrevision team.
</div>

## Features
* **AppX manager** - remove inbox/bloat packages for all users, with deprovisioning so they do not come back.
* **WinSxS removal packages** - install/uninstall the MithenOS component packages.
* **Microsoft Store apps** - search and install Store apps without the Store.
* **Windows customizations** - Explorer, taskbar, Start and notification tweaks applied by a bundled, fully offline Windhawk engine (2.0.0-alpha.7) that lives in the MithenTool folder. It behaves like a small Windhawk: no separate install, no tray icon, no update check. If a real Windhawk is installed, the page stays disabled and nothing is touched; uninstalling MithenTool removes the engine, its service and its registry data.
* **Tweaks** - performance, security, personalization, updates and utilities toggles.
* **System Monitor** - about 80 checks that everything the playbook disabled or removed is still in that state, with a per-item **Fix**, **Fix all**, and an automatic scan on open.
* **Leftovers Cleaner** - finds leftovers of programs whose own uninstaller is already gone (Add/Remove entries, Open with and file associations, registry keys, program folders, scheduled tasks, services, startup items) and removes them in a two-pass run. Everything is backed up first (`reg` exports, task XML, quarantined folders) and can be restored with one click.
* **Tools** - one-click launchers for Microsoft Activation Scripts (MAS) and ChrisTitusTech WinUtil, plus a GitHub link for every Mithen app.
* **CLI** - every feature is also a `mithentool.exe` verb, which is what the MithenOS playbook calls.
* Available in 16 languages.
## How to use
* Install `MithenTool-Setup.exe` from the [latest release](https://github.com/catchem88/mithen-tool/releases/latest) (the MithenOS playbook installs and bundles it automatically).
* Launch `mithentoolw.exe` for the GUI, or use the CLI next to it:
  * `mithentool appx --all-users --remove Microsoft.Copilot`
  * `mithentool monitor --scan` (add `--fix` to restore drifted items)
  * `mithentool cleanup --scan` (add `--apply` to remove, `--restore` to undo a run)
  * `mithentool tweaks`, `mithentool winsxs`, `mithentool store`## Supported platforms
* Windows 10/11 (x64). Must run elevated - it edits HKLM, services, Windows features and file associations.
* Designed for [MithenOS](https://github.com/catchem88/mithen-os) (or ReviOS). On stock Windows it runs with a warning, but some features expect the playbook to be applied.
## Part of MithenApps
* No telemetry
* No update checking (use it as a tool, update it when you find issues only)
* No background service. Closed when it's closed.
* Every change it makes is backed up and reversible
* Prioritizing user-ergonomics
## Support and Sponsor the OG creator!
[Revision Tool](https://github.com/meetrevision/revision-tool)
## Credits
* [meetrevision](https://github.com/meetrevision) - authors of the [Revision Tool](https://github.com/meetrevision/revision-tool) that MithenTool is based on.
* [AME](https://ameliorated.io) - the playbook format and wizard MithenOS builds on.
* [Windhawk](https://windhawk.net) by [Ramen Software](https://github.com/ramensoftware) - the mod engine bundled (headless, offline) for the Windows customizations page, and the authors of the mods it ships.
## License
MithenTool is licensed under the [GNU General Public License v3.0](LICENSE).