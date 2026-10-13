import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';

import '../../../core/services/win_registry_service.dart';
import '../../../utils.dart';
import '../domain/entities/orphan_item.dart';
import 'cleanup_backup.dart';

/// Finds leftovers of removed programs and deletes them.
final class const CleanupRepository() {
  static const String _servicesPath = r'SYSTEM\CurrentControlSet\Services';

  static const List<String> _windowsOwned = [
    'common files',
    'dotnet',
    'internet explorer',
    'modifiablewindowsapps',
    'msbuild',
    'reference assemblies',
    'uninstall information',
    'wixtoolset',
  ];

  /// Windows-owned trees are never treated as orphaned program folders.
  bool _isWindowsOwned(String name) {
    final String lower = name.toLowerCase();
    return lower.startsWith('windows') ||
        lower.startsWith('microsoft') ||
        lower.startsWith('.net') ||
        _windowsOwned.contains(lower);
  }

  /// Microsoft-owned items are hidden from the leftover scanner.
  bool _isMicrosoftBrand(String? text) => text != null && text.toLowerCase().contains('microsoft');

  /// Paths inside the Windows directory are Windows components, not leftovers.
  bool _isWindowsComponent(String? path) =>
      path != null && path.toLowerCase().startsWith(_windowsDirectory().toLowerCase());

  /// Packaged apps register `AppX<hash>` ProgIds that stop resolving once the
  /// package is removed - the AppX manager owns those, not the leftover cleaner.
  bool _isPackagedProgId(String progId) => progId.toUpperCase().startsWith('APPX');

  List<String> _subKeys(BaseRegistryKey hive, String path) {
    try {
      final RegistryKey key = hive.open(path);
      try {
        return key.keys.toList(growable: false);
      } finally {
        key.close();
      }
    } catch (_) {
      return const [];
    }
  }

  Map<String, RegistryValue> _values(BaseRegistryKey hive, String path) {
    try {
      final RegistryKey key = hive.open(path);
      try {
        return <String, RegistryValue>{
          for (final ({String name, RegistryValue value}) entry in key.values)
            entry.name: entry.value,
        };
      } finally {
        key.close();
      }
    } catch (_) {
      return const {};
    }
  }

  String? _readString(Map<String, RegistryValue> values, String name) {
    final RegistryValue? value = values[name];
    return switch (value) {
      StringValue(:final String value) => value,
      UnexpandedStringValue(:final String value) => value,
      LinkValue(:final String value) => value,
      _ => null,
    };
  }

  int? _readInt(Map<String, RegistryValue> values, String name) {
    final RegistryValue? value = values[name];
    return switch (value) {
      DwordValue(:final int value) => value,
      QwordValue(:final int value) => value,
      _ => null,
    };
  }

  String _windowsDirectory() => Platform.environment['SystemRoot'] ?? r'C:\Windows';

  /// Expands registry environment variables and device path prefixes.
  String _expand(String value) {
    final variables = <String, String?>{
      'SystemRoot': Platform.environment['SystemRoot'],
      'windir': Platform.environment['SystemRoot'],
      'ProgramFiles': Platform.environment['ProgramFiles'],
      'ProgramFiles(x86)': Platform.environment['ProgramFiles(x86)'],
      'ProgramData': Platform.environment['ProgramData'],
      'LOCALAPPDATA': Platform.environment['LOCALAPPDATA'],
      'APPDATA': Platform.environment['APPDATA'],
      'USERPROFILE': Platform.environment['USERPROFILE'],
    };
    String out = value.trim();
    if (out.startsWith(r'\??\')) out = out.substring(4);
    if (out.toLowerCase().startsWith(r'\systemroot')) {
      out = '${_windowsDirectory()}${out.substring(11)}';
    }
    for (final MapEntry<String, String?> entry in variables.entries) {
      final String? replacement = entry.value;
      if (replacement == null) continue;
      // The registry writes %systemroot% in any case.
      out = out.replaceAll(RegExp('%${entry.key}%', caseSensitive: false), replacement);
    }
    // Driver ImagePath values are often relative to the Windows directory
    // (`System32\drivers\atapi.sys`).
    if (out.isNotEmpty && !out.contains(':') && !out.startsWith(r'\') && !out.contains('%')) {
      final joined = '${_windowsDirectory()}\\$out';
      if (_fileExists(joined) || _dirExists(joined)) out = joined;
    }
    return out;
  }

  /// Extracts the executable path from a command line, or null when there is none.
  ///
  /// Handles quoted paths, `DisplayIcon` resource indexes and unquoted paths with
  /// spaces. Bare commands that live on PATH (`winget`, `msiexec`) return null -
  /// they are never treated as missing.
  String? _executable(String? command) {
    if (command == null || command.trim().isEmpty) return null;
    final String trimmed = command.trim();
    if (trimmed.startsWith('"')) {
      final int end = trimmed.indexOf('"', 1);
      final String quoted = end > 1 ? trimmed.substring(1, end) : trimmed.substring(1);
      return _stripResourceIndex(_expand(quoted));
    }
    final List<String> parts = _expand(trimmed).split(RegExp(r'\s+'));
    if (parts.length == 1) return _stripResourceIndex(parts.first);
    // A bare first token (rundll32.exe, msiexec) lives on PATH - never missing.
    if (!parts.first.contains(r'\') && !parts.first.contains('/')) return null;
    String candidate = parts.first;
    for (var i = 1; i < parts.length; i++) {
      final next = '$candidate ${parts[i]}';
      if (_fileExists(next)) return _stripResourceIndex(next);
      candidate = next;
    }
    final String resolved = _stripResourceIndex(candidate);
    if (!resolved.contains(r'\') && !resolved.contains('/')) return null;
    return resolved;
  }

  /// Drops the `,index` suffix of `DisplayIcon` values.
  String _stripResourceIndex(String path) => path.replaceFirst(RegExp(r',\s*-?\d+\s*$'), '').trim();

  /// True when [path] is an existing file, without throwing on bad paths.
  bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// True when [path] points at an existing file or folder.
  bool _exists(String? path) {
    if (path == null || path.isEmpty) return false;
    if (!path.contains(r'\') && !path.contains('/')) return false;
    if (path.contains('%')) return false;
    try {
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      // Malformed registry paths (stray quotes, invalid characters) read as gone.
      return false;
    }
  }

  /// True when [path] is an existing directory, without throwing on bad paths.
  bool _dirExists(String path) {
    if (path.isEmpty) return false;
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, Object?>>> _runJson(String script) async {
    try {
      return await _parseJson(script);
    } catch (error) {
      logger.w('cleanup: PowerShell scan failed', error: error);
      return const [];
    }
  }

  Future<List<Map<String, Object?>>> _parseJson(String script) async {
    final ProcessResult result = await runPSCommand(
      '$script | ConvertTo-Json -Depth 3 -Compress',
      loggerInfoOutput: false,
    );
    final String output = result.stdout.toString().trim();
    if (output.isEmpty) return const [];
    try {
      final Object? decoded = jsonDecode(output);
      if (decoded is Map<String, Object?>) return [decoded];
      if (decoded is List) {
        return decoded.whereType<Map<String, Object?>>().toList(growable: false);
      }
    } catch (error) {
      logger.w('cleanup: could not parse PowerShell output', error: error);
    }
    return const [];
  }

  /// Parses a `HIVE\key\path[::value]` cleanup target.
  ({BaseRegistryKey hive, String hiveName, String path, String? value})? _registryRef(
    String target,
  ) {
    final int separator = target.indexOf(r'\');
    if (separator < 1) return null;
    final String hiveName = target.substring(0, separator);
    final String rest = target.substring(separator + 1);
    final int valueSeparator = rest.lastIndexOf('::');
    final BaseRegistryKey hive = switch (hiveName) {
      'HKCU' => CURRENT_USER,
      'HKCR' => CLASSES_ROOT,
      _ => LOCAL_MACHINE,
    };
    return (
      hive: hive,
      hiveName: hiveName,
      path: valueSeparator == -1 ? rest : rest.substring(0, valueSeparator),
      value: valueSeparator == -1 ? null : rest.substring(valueSeparator + 2),
    );
  }

  /// Scans the system category by category.
  ///
  /// When a category fails, [onError] decides whether to skip it (true) or abort
  /// the whole scan (false - throws [ScanCancelledException]). Without [onError]
  /// failing categories are skipped and logged.
  Future<CleanupReport> scan({
    Future<bool> Function(OrphanKind kind, Object error)? onError,
  }) async {
    final items = <OrphanItem>[];
    final liveLocations = <String>{};
    final liveExecutables = <String>{};
    final removedProgramNames = <String>{};

    Future<void> runStep(OrphanKind kind, Future<List<OrphanItem>> Function() scanner) async {
      try {
        final List<OrphanItem> found = await scanner();
        items.addAll(found);
        if (kind == OrphanKind.uninstallEntry) {
          for (final item in found) {
            final String? appName = item.appName;
            if (appName != null) removedProgramNames.add(appName);
          }
        }
      } catch (error) {
        logger.w('cleanup: ${kind.name} scan failed', error: error);
        final bool skip = await onError?.call(kind, error) ?? true;
        if (!skip) throw const ScanCancelledException();
      }
    }

    await runStep(
      OrphanKind.uninstallEntry,
      () async => _scanUninstallEntries(liveLocations, liveExecutables),
    );
    await runStep(OrphanKind.fileAssociation, () async => _scanFileAssociations());
    await runStep(OrphanKind.registry, () async => _scanRegistryLeftovers());
    await runStep(OrphanKind.service, () async => _scanServices(liveExecutables));
    await runStep(OrphanKind.scheduledTask, () async => _scanTasks(liveExecutables));
    await runStep(OrphanKind.startupEntry, () async => _scanStartup(liveExecutables));
    _collectMsiLocations(liveLocations);
    await _collectStartMenuTargets(liveExecutables, liveLocations);
    await runStep(
      OrphanKind.folder,
      () async => _scanFolders(liveLocations, liveExecutables, removedProgramNames),
    );
    return CleanupReport(items: items, scannedAt: DateTime.now());
  }

  /// Adds the install folders Windows Installer (MSI) products recorded.
  ///
  /// MSI entries often have no `InstallLocation` in Add/Remove Programs, which
  /// would make their folders look unclaimed.
  void _collectMsiLocations(Set<String> liveLocations) {
    const root = r'SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData';
    for (final String userSid in _subKeys(LOCAL_MACHINE, root)) {
      final products = '$root\\$userSid\\Products';
      for (final String product in _subKeys(LOCAL_MACHINE, products)) {
        final String? location = WinRegistryService.readString(
          LOCAL_MACHINE,
          '$products\\$product\\InstallProperties',
          'InstallLocation',
        );
        if (location == null || location.trim().isEmpty) continue;
        final String expanded = _expand(location);
        if (_dirExists(expanded)) {
          liveLocations.add(p.normalize(expanded.toLowerCase()));
        }
      }
    }
  }

  /// Adds the targets of every Start menu shortcut, which claim their folders.
  Future<void> _collectStartMenuTargets(
    Set<String> liveExecutables,
    Set<String> liveLocations,
  ) async {
    final List<Map<String, Object?>> rows = await _runJson(
      r'$shell = New-Object -ComObject WScript.Shell; '
      r'@("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", '
      r'"$env:APPDATA\Microsoft\Windows\Start Menu\Programs") | '
      r'ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter *.lnk '
      r'-ErrorAction SilentlyContinue | ForEach-Object { '
      r'[pscustomobject]@{ Target = $shell.CreateShortcut($_.FullName).TargetPath } } }',
    );
    for (final row in rows) {
      final String target = (row['Target'] as String?) ?? '';
      if (target.trim().isEmpty) continue;
      final String executable = _expand(target);
      if (!_exists(executable)) continue;
      liveExecutables.add(p.normalize(executable.toLowerCase()));
      liveLocations.add(p.normalize(p.dirname(executable).toLowerCase()));
    }
  }

  static const List<(String, String)> _uninstallRoots = [
    ('HKLM', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'),
    ('HKLM', r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'),
    ('HKCU', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'),
  ];

  /// Registry entries in Add/Remove Programs whose program is already gone.
  List<OrphanItem> _scanUninstallEntries(Set<String> liveLocations, Set<String> liveExecutables) {
    final items = <OrphanItem>[];
    for (final (String hiveName, String root) in _uninstallRoots) {
      final BaseRegistryKey hive = hiveName == 'HKCU' ? CURRENT_USER : LOCAL_MACHINE;
      for (final String sub in _subKeys(hive, root)) {
        final path = '$root\\$sub';
        final Map<String, RegistryValue> values = _values(hive, path);
        final String? name = _readString(values, 'DisplayName');
        if (name == null || name.trim().isEmpty) continue;
        if (_isMicrosoftBrand(name) || _isMicrosoftBrand(_readString(values, 'Publisher'))) {
          continue;
        }
        final String uninstall = _readString(values, 'UninstallString') ?? '';
        final String quiet = _readString(values, 'QuietUninstallString') ?? '';
        final String location = _expand(_readString(values, 'InstallLocation') ?? '');
        final String? uninstallExe = _executable(uninstall) ?? _executable(quiet);
        final String? icon = _executable(_readString(values, 'DisplayIcon'));
        final bool msiexec = '$uninstall $quiet'.toLowerCase().contains('msiexec');
        final bool exeGone = uninstallExe != null && !msiexec && !_exists(uninstallExe);
        final bool locationGone = location.isNotEmpty && !_dirExists(location);
        final bool iconGone = icon != null && !_exists(icon);
        // Every pointer into the install must be gone before the entry counts as
        // orphaned - one living path means the program is still there.
        final bool orphaned = msiexec
            ? locationGone && iconGone
            : exeGone && (location.isEmpty || locationGone) && (icon == null || iconGone);
        if (orphaned) {
          items.add(
            OrphanItem(
              id: 'uninstall:$hiveName\\$path',
              kind: OrphanKind.uninstallEntry,
              title: name,
              detail: exeGone
                  ? 'Uninstaller is missing: $uninstallExe'
                  : 'Install location is missing: $location',
              target: '$hiveName\\$path',
              appName: name,
              publisher: _readString(values, 'Publisher'),
            ),
          );
          continue;
        }
        if (location.isNotEmpty && _dirExists(location)) {
          liveLocations.add(p.normalize(location.toLowerCase()));
        }
        if (uninstallExe != null) {
          liveExecutables.add(p.normalize(uninstallExe.toLowerCase()));
        }
        if (icon != null) {
          liveExecutables.add(p.normalize(icon.toLowerCase()));
          liveLocations.add(p.normalize(p.dirname(icon).toLowerCase()));
        }
      }
    }
    return items;
  }

  List<(String, BaseRegistryKey)> get _userHives => <(String, BaseRegistryKey)>[
    ('HKLM', LOCAL_MACHINE),
    ('HKCU', CURRENT_USER),
  ];

  /// `Applications` registrations behind the Open with list.
  List<OrphanItem> _scanApplications() {
    final items = <OrphanItem>[];
    for (final (String hiveName, BaseRegistryKey hive) in _userHives) {
      const root = r'SOFTWARE\Classes\Applications';
      for (final String sub in _subKeys(hive, root)) {
        if (_isMicrosoftBrand(sub)) continue;
        final path = '$root\\$sub';
        final String? exe = _executable(
          _readString(_values(hive, '$path\\shell\\open\\command'), ''),
        );
        if (_isWindowsComponent(exe)) continue;
        if (exe == null || _exists(exe)) continue;
        items.add(
          OrphanItem(
            id: 'applications:$hiveName:$sub',
            kind: OrphanKind.fileAssociation,
            title: sub,
            detail: 'Registered program is missing: $exe',
            target: '$hiveName\\$path',
            appName: p.basenameWithoutExtension(sub),
          ),
        );
      }
    }
    return items;
  }

  /// Resolves a bare executable name such as `notepad.exe` to a full path.
  String? _resolveExecutableName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final String value = name.trim();
    if (value.contains(r'\') || value.contains('/')) return _expand(value);
    for (final directory in <String>[
      '${_windowsDirectory()}\\system32',
      _windowsDirectory(),
      '${_windowsDirectory()}\\SysWOW64',
    ]) {
      final String candidate = p.join(directory, value);
      if (File(candidate).existsSync()) return candidate;
    }
    return p.join('${_windowsDirectory()}\\system32', value);
  }

  /// True when a ProgId is still registered for a present program.
  ///
  /// [CLASSES_ROOT] is the merged view and also sees ProgIds of packaged apps
  /// that never appear under HKLM/HKCU `Software\Classes` literally.
  bool _progIdExists(String progId, Set<String> registeredApplications) {
    final String trimmed = progId.trim();
    if (trimmed.isEmpty) return true;
    final String lower = trimmed.toLowerCase();
    if (lower.startsWith(r'applications\')) {
      return registeredApplications.contains(lower.split(r'\').last);
    }
    return _keyExistsAnyHive('SOFTWARE\\Classes\\$trimmed');
  }

  bool _keyExistsAnyHive(String path) =>
      WinRegistryService.keyExists(LOCAL_MACHINE, path) ||
      WinRegistryService.keyExists(CURRENT_USER, path) ||
      WinRegistryService.keyExists(CLASSES_ROOT, path);

  /// Open with, default program and ProgId registrations of gone programs.
  List<OrphanItem> _scanFileAssociations() {
    final Set<String> registeredApplications = _subKeys(
      CLASSES_ROOT,
      r'Applications',
    ).map((String name) => name.toLowerCase()).toSet();
    return <OrphanItem>[
      ..._scanApplications(),
      ..._scanRegisteredApplications(),
      ..._scanFileExts(registeredApplications),
    ];
  }

  /// Open with entries for extensions whose program is gone.
  List<OrphanItem> _scanFileExts(Set<String> registered) {
    final items = <OrphanItem>[];
    const root = r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts';
    for (final String ext in _subKeys(CURRENT_USER, root)) {
      final path = '$root\\$ext';
      final Map<String, RegistryValue> openWithList = _values(CURRENT_USER, '$path\\OpenWithList');
      for (final MapEntry<String, RegistryValue> entry in openWithList.entries) {
        if (entry.key.toUpperCase() == 'MRULIST') continue;
        final String? executableName = _readString(openWithList, entry.key);
        if (executableName == null || executableName.trim().isEmpty) continue;
        // Bare names (Cheat Engine.exe, winget) cannot be proven missing - the
        // app may live anywhere. Only full paths are checked.
        if (!executableName.contains(r'\') && !executableName.contains('/')) continue;
        final String? resolved = _resolveExecutableName(executableName);
        if (resolved != null && _exists(resolved)) continue;
        if (_isWindowsComponent(resolved) || _isMicrosoftBrand(executableName)) continue;
        items.add(
          OrphanItem(
            id: 'openwith:$ext:${entry.key}',
            kind: OrphanKind.fileAssociation,
            title: executableName,
            detail: 'Offered for $ext but it is not installed',
            target: 'HKCU\\$path\\OpenWithList::${entry.key}',
            appName: p.basenameWithoutExtension(executableName),
          ),
        );
      }
      for (final String progId in _values(CURRENT_USER, '$path\\OpenWithProgids').keys) {
        // Single letters and other junk without a dot are not real ProgIds.
        if (!progId.contains('.')) continue;
        // Packaged apps (`AppX<hash>`) are the AppX manager's domain, and their
        // handlers die with the package on purpose.
        if (_isPackagedProgId(progId)) continue;
        if (_progIdExists(progId, registered)) continue;
        if (_isMicrosoftBrand(progId)) continue;
        items.add(
          OrphanItem(
            id: 'openwithprogid:$ext:$progId',
            kind: OrphanKind.fileAssociation,
            title: progId,
            detail: 'Registered for $ext but is not installed',
            target: 'HKCU\\$path\\OpenWithProgids::$progId',
            appName: progId,
          ),
        );
      }
      final String? progId = _readString(_values(CURRENT_USER, '$path\\UserChoice'), 'ProgId');
      if (progId == null || progId.isEmpty) continue;
      if (_isPackagedProgId(progId)) continue;
      if (_progIdExists(progId, registered)) continue;
      if (_isMicrosoftBrand(progId)) continue;
      items.add(
        OrphanItem(
          id: 'userchoice:$ext',
          kind: OrphanKind.fileAssociation,
          title: progId,
          detail: 'Unavailable handler for $ext',
          target: 'HKCU\\$path\\UserChoice',
          appName: progId,
        ),
      );
    }
    return items;
  }

  /// `RegisteredApplications` entries whose capabilities key is gone.
  List<OrphanItem> _scanRegisteredApplications() {
    final items = <OrphanItem>[];
    const root = r'SOFTWARE\RegisteredApplications';
    for (final (String hiveName, BaseRegistryKey hive) in _userHives) {
      final Map<String, RegistryValue> values = _values(hive, root);
      for (final MapEntry<String, RegistryValue> entry in values.entries) {
        final String? capabilities = _readString(values, entry.key);
        if (capabilities == null || capabilities.isEmpty) continue;
        if (_isMicrosoftBrand(entry.key) || _isMicrosoftBrand(capabilities)) continue;
        // The value data is already relative to the SOFTWARE root
        // (`Software\Clients\...`, `SOFTWARE\Vendor\...`) - do not prefix it again.
        if (_keyExistsAnyHive(capabilities)) continue;
        items.add(
          OrphanItem(
            id: 'registeredapplication:$hiveName:${entry.key}',
            kind: OrphanKind.fileAssociation,
            title: entry.key,
            detail: 'Listed in Default apps but the program is gone',
            target: '$hiveName\\$root::${entry.key}',
            appName: entry.key,
          ),
        );
      }
    }
    return items;
  }

  static const Set<String> _notProgIdNames = {
    'appid',
    'applications',
    'clsid',
    'directory',
    'drive',
    'exefile',
    'folder',
    'installer',
    'interface',
    'media type',
    'medial type',
    'mime',
    'protocols',
    'record',
    'systemfileassociations',
    'typelib',
    'wow6432node',
  };

  bool _looksLikeProgId(String name) =>
      name.contains('.') && !_notProgIdNames.contains(name.toLowerCase());

  /// App Paths and ProgId keys that point at programs that are gone.
  List<OrphanItem> _scanRegistryLeftovers() {
    final items = <OrphanItem>[];
    for (final root in <String>[
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
      r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
    ]) {
      for (final String sub in _subKeys(LOCAL_MACHINE, root)) {
        final path = '$root\\$sub';
        final String? exe = _executable(_readString(_values(LOCAL_MACHINE, path), ''));
        if (_isMicrosoftBrand(sub) || _isMicrosoftBrand(exe)) continue;
        if (_isWindowsComponent(exe)) continue;
        if (exe == null || _exists(exe)) continue;
        items.add(
          OrphanItem(
            id: 'apppath:$sub',
            kind: OrphanKind.registry,
            title: sub,
            detail: 'App Paths entry points at a missing program: $exe',
            target: 'HKLM\\$path',
            appName: sub,
          ),
        );
      }
    }
    for (final (String hiveName, BaseRegistryKey hive) in _userHives) {
      const root = r'SOFTWARE\Classes';
      for (final String sub in _subKeys(hive, root)) {
        if (!_looksLikeProgId(sub)) continue;
        if (_isMicrosoftBrand(sub)) continue;
        final path = '$root\\$sub';
        final String? exe = _executable(
          _readString(_values(hive, '$path\\shell\\open\\command'), ''),
        );
        if (_isWindowsComponent(exe)) continue;
        if (exe == null || _exists(exe)) continue;
        items.add(
          OrphanItem(
            id: 'progid:$hiveName:$sub',
            kind: OrphanKind.registry,
            title: sub,
            detail: 'File type registration points at a missing program: $exe',
            target: '$hiveName\\$path',
            appName: sub,
          ),
        );
      }
    }
    return items;
  }

  /// Services whose executable or driver file no longer exists.
  List<OrphanItem> _scanServices(Set<String> liveExecutables) {
    final items = <OrphanItem>[];
    final String windowsDirectory = _windowsDirectory().toLowerCase();
    for (final String name in _subKeys(LOCAL_MACHINE, _servicesPath)) {
      final path = '$_servicesPath\\$name';
      final Map<String, RegistryValue> values = _values(LOCAL_MACHINE, path);
      final String? imagePath = _readString(values, 'ImagePath');
      if (imagePath == null || imagePath.trim().isEmpty) continue;
      final String? executable = _executable(imagePath);
      if (executable == null) continue;
      final String lower = executable.toLowerCase();
      if (_isMicrosoftBrand(executable)) continue;
      if (lower.startsWith(windowsDirectory) || p.basename(lower) == 'svchost.exe') {
        liveExecutables.add(p.normalize(lower));
        continue;
      }
      if (_exists(executable)) {
        liveExecutables.add(p.normalize(lower));
        continue;
      }
      final bool driver = lower.endsWith('.sys') || ((_readInt(values, 'Type') ?? 0) & 0x3) != 0;
      items.add(
        OrphanItem(
          id: 'service:$name',
          kind: OrphanKind.service,
          title: name,
          detail: driver
              ? 'Driver file is missing: $executable'
              : 'Service executable is missing: $executable',
          target: name,
          appName: p.basenameWithoutExtension(executable),
        ),
      );
    }
    return items;
  }

  /// Scheduled tasks whose action points at a program that is gone.
  Future<List<OrphanItem>> _scanTasks(Set<String> liveExecutables) async {
    final List<Map<String, Object?>> rows = await _runJson(
      r'Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object { '
      r'$action = @($_.Actions)[0]; '
      r'[pscustomobject]@{ Path = $_.TaskPath; Name = $_.TaskName; '
      r'Exe = "$($action.Execute)"; Args = "$($action.Arguments)" } }',
    );
    final items = <OrphanItem>[];
    final String windowsDirectory = _windowsDirectory().toLowerCase();
    for (final row in rows) {
      final exe = row['Exe'] as String?;
      final String taskPath = (row['Path'] as String?) ?? r'\';
      final String taskName = (row['Name'] as String?) ?? '';
      if (taskName.isEmpty || exe == null || exe.trim().isEmpty) continue;
      final String executable = _expand(exe);
      final String lower = executable.toLowerCase();
      if (_isMicrosoftBrand(executable) || _isMicrosoftBrand(taskPath)) continue;
      if (lower.startsWith(windowsDirectory) || p.basename(lower) == 'svchost.exe') {
        liveExecutables.add(p.normalize(lower));
        continue;
      }
      if (_exists(executable)) {
        liveExecutables.add(p.normalize(lower));
        continue;
      }
      items.add(
        OrphanItem(
          id: 'task:$taskPath$taskName',
          kind: OrphanKind.scheduledTask,
          title: taskName,
          detail: 'Task action is missing: $executable',
          target: '$taskPath$taskName',
          appName: p.basenameWithoutExtension(executable),
        ),
      );
    }
    return items;
  }

  /// Startup entries whose program is gone.
  Future<List<OrphanItem>> _scanStartup(Set<String> liveExecutables) async {
    final items = <OrphanItem>[];
    const runKeys = <(String, String)>[
      ('HKLM', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'),
      ('HKLM', r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'),
      ('HKCU', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'),
      ('HKLM', r'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'),
      ('HKLM', r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'),
      ('HKCU', r'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'),
    ];
    for (final (String hiveName, String path) in runKeys) {
      final BaseRegistryKey hive = hiveName == 'HKCU' ? CURRENT_USER : LOCAL_MACHINE;
      final Map<String, RegistryValue> values = _values(hive, path);
      for (final MapEntry<String, RegistryValue> entry in values.entries) {
        final String? executable = _executable(_readString(values, entry.key));
        if (executable == null) continue;
        if (_isMicrosoftBrand(executable) || _isMicrosoftBrand(entry.key)) continue;
        if (_exists(executable)) {
          liveExecutables.add(p.normalize(executable.toLowerCase()));
          continue;
        }
        if (p.basename(executable.toLowerCase()) == 'svchost.exe') continue;
        items.add(
          OrphanItem(
            id: 'startup:$hiveName:$path:${entry.key}',
            kind: OrphanKind.startupEntry,
            title: entry.key,
            detail: 'Startup target is missing: $executable',
            target: '$hiveName\\$path::${entry.key}',
            appName: entry.key,
          ),
        );
      }
    }
    items.addAll(await _scanStartupFolders(liveExecutables));
    return items;
  }

  /// Startup folder items whose target is gone.
  Future<List<OrphanItem>> _scanStartupFolders(Set<String> liveExecutables) async {
    final List<Map<String, Object?>> rows = await _runJson(
      r'$shell = New-Object -ComObject WScript.Shell; '
      r'@("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", '
      r'"$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup") | '
      r'ForEach-Object { Get-ChildItem -LiteralPath $_ -File -ErrorAction SilentlyContinue | '
      r'ForEach-Object { $target = if ($_.Extension -eq ".lnk") { '
      r'$shell.CreateShortcut($_.FullName).TargetPath } else { $_.FullName }; '
      r'[pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Target = "$target" } } }',
    );
    final items = <OrphanItem>[];
    for (final row in rows) {
      final String target = (row['Target'] as String?) ?? '';
      final String name = (row['Name'] as String?) ?? '';
      final String entryPath = (row['Path'] as String?) ?? '';
      if (target.isEmpty || entryPath.isEmpty) continue;
      final String executable = _expand(target);
      if (_isMicrosoftBrand(executable) || _isMicrosoftBrand(name)) continue;
      if (_exists(executable)) {
        liveExecutables.add(p.normalize(executable.toLowerCase()));
        continue;
      }
      items.add(
        OrphanItem(
          id: 'startupfolder:$entryPath',
          kind: OrphanKind.startupEntry,
          title: name,
          detail: 'Startup item points at a missing target: $executable',
          target: entryPath,
          appName: p.basenameWithoutExtension(name),
        ),
      );
    }
    return items;
  }

  /// Program folders left behind by programs the Add/Remove list says are gone.
  ///
  /// A folder is only flagged when its name matches one of those removed
  /// programs, so installed software can never be flagged.
  List<OrphanItem> _scanFolders(
    Set<String> liveLocations,
    Set<String> liveExecutables,
    Set<String> removedProgramNames,
  ) {
    final items = <OrphanItem>[];
    final List<String> roots = <String?>[
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)'],
      if (Platform.environment['LOCALAPPDATA'] != null)
        p.join(Platform.environment['LOCALAPPDATA']!, 'Programs'),
    ].whereType<String>().toList(growable: false);
    for (final root in roots) {
      if (!_dirExists(root)) continue;
      List<FileSystemEntity> children;
      try {
        children = Directory(root).listSync();
      } catch (error) {
        logger.w('cleanup: could not list $root', error: error);
        continue;
      }
      for (final Directory directory in children.whereType<Directory>()) {
        final String name = p.basename(directory.path);
        if (_isWindowsOwned(name)) continue;
        final String normalized = p.normalize(directory.path.toLowerCase());
        if (liveLocations.contains(normalized)) continue;
        if (_isReferenced(directory, liveExecutables)) continue;
        final String? removedProgram = _removedProgramFor(name, removedProgramNames);
        if (removedProgram == null) continue;
        if (!_looksLikeProgramFolder(directory)) continue;
        items.add(
          OrphanItem(
            id: 'folder:$normalized',
            kind: OrphanKind.folder,
            title: name,
            detail: 'Left over from the removed program "$removedProgram"',
            target: directory.path,
            appName: name,
            quarantineOnly: true,
          ),
        );
      }
    }
    return items;
  }

  /// The removed program a folder name belongs to, if any.
  String? _removedProgramFor(String folderName, Set<String> removedProgramNames) {
    final String folder = folderName.toLowerCase();
    for (final name in removedProgramNames) {
      final List<String> tokens = name.toLowerCase().split(RegExp(r'[\s\-_]+'));
      if (tokens.contains(folder)) return name;
    }
    return null;
  }

  bool _isReferenced(Directory directory, Set<String> liveExecutables) {
    final String prefix = p.normalize(directory.path.toLowerCase());
    return liveExecutables.any((String path) => path.startsWith('$prefix\\'));
  }

  bool _looksLikeProgramFolder(Directory directory) {
    try {
      return directory.listSync(recursive: true, followLinks: false).take(400).any((
        FileSystemEntity entity,
      ) {
        if (entity is! File) return false;
        final String extension = p.extension(entity.path).toLowerCase();
        return extension == '.exe' || extension == '.dll';
      });
    } catch (_) {
      return false;
    }
  }

  /// Removes [items] one by one after backing every change up.
  ///
  /// [onProgress] reports the item being worked on, and [isCancelled] can stop
  /// the run between items; whatever was already removed stays recorded in the
  /// backup, so a cancelled run remains fully reversible.
  Future<CleanupOutcome> clean(
    List<OrphanItem> items,
    CleanupBackup backup, {
    void Function(OrphanItem item, int index, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <OrphanActionResult>[];
    for (var index = 0; index < items.length; index++) {
      if (isCancelled?.call() ?? false) break;
      final OrphanItem item = items[index];
      onProgress?.call(item, index + 1, items.length);
      try {
        final String message = await _apply(item, backup);
        results.add(OrphanActionResult(item: item, ok: true, message: message));
      } catch (error) {
        logger.w('cleanup: could not remove ${item.target}', error: error);
        results.add(OrphanActionResult(item: item, ok: false, message: error.toString()));
      }
    }
    await backup.save();
    return CleanupOutcome(results: results, backupPath: backup.directory.path);
  }

  /// Runs scan + removal passes until the system comes out clean.
  ///
  /// Removals cascade (removing an Add/Remove entry makes its folder a leftover,
  /// which makes the tasks pointing into it leftovers...), so after each removal
  /// pass the system is scanned again. Stops when a pass finds nothing new, when
  /// [maxPasses] is reached, or when [isCancelled] fires. [excludedIds] are item
  /// ids the user deliberately kept - they are never removed. The final scan
  /// returns everything that still matches as [CleanupRunResult.remaining].
  Future<CleanupRunResult> runPasses({
    CleanupReport? initialReport,
    int maxPasses = 2,
    Set<String> excludedIds = const <String>{},
    Future<bool> Function(OrphanKind kind, Object error)? onError,
    void Function(String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final CleanupBackup backup = CleanupBackup.create();
    final passes = <CleanupPassResult>[];
    var remaining = const <OrphanItem>[];

    for (var pass = 1; pass <= maxPasses; pass++) {
      if (isCancelled?.call() ?? false) break;
      CleanupReport report;
      if (pass == 1 && initialReport != null) {
        report = initialReport;
      } else {
        onProgress?.call('Pass $pass/$maxPasses - scanning');
        report = await scan(onError: onError);
      }
      remaining = report.items;
      final List<OrphanItem> found = report.items
          .where((OrphanItem item) => !excludedIds.contains(item.id))
          .toList(growable: false);
      if (found.isEmpty) break;

      final results = <OrphanActionResult>[];
      for (var index = 0; index < found.length; index++) {
        if (isCancelled?.call() ?? false) break;
        final OrphanItem item = found[index];
        onProgress?.call(
          'Pass $pass/$maxPasses - removing (${index + 1}/${found.length}) ${item.title}',
        );
        try {
          final String message = await _apply(item, backup);
          results.add(OrphanActionResult(item: item, ok: true, message: message));
        } catch (error) {
          logger.w('cleanup: could not remove ${item.target}', error: error);
          results.add(OrphanActionResult(item: item, ok: false, message: error.toString()));
        }
      }
      final int removed = results.where((OrphanActionResult result) => result.ok).length;
      passes.add(
        CleanupPassResult(
          pass: pass,
          removed: removed,
          failed: results.length - removed,
          results: results,
        ),
      );
    }

    onProgress?.call('Verifying');
    final CleanupReport finalReport = await scan(onError: onError);
    remaining = finalReport.items
        .where((OrphanItem item) => !excludedIds.contains(item.id))
        .toList(growable: false);
    await backup.save();
    return CleanupRunResult(
      passes: passes,
      remaining: remaining,
      backupPath: backup.directory.path,
    );
  }

  Future<String> _apply(OrphanItem item, CleanupBackup backup) async {
    switch (item.kind) {
      case OrphanKind.uninstallEntry:
      case OrphanKind.fileAssociation:
      case OrphanKind.registry:
        return _deleteRegistryTarget(item, backup);
      case OrphanKind.startupEntry:
        return _deleteStartupEntry(item, backup);
      case OrphanKind.folder:
        final String? moved = await backup.quarantineFolder(item.target);
        if (moved == null) throw StateError('Could not move ${item.target}');
        backup.record('folder', item.target, <String, Object?>{'quarantine': moved});
        return 'Moved to quarantine';
      case OrphanKind.scheduledTask:
        String taskPath = p.dirname(item.target);
        if (!taskPath.endsWith(r'\')) taskPath = '$taskPath\\';
        final String taskName = p.basename(item.target);
        final String? taskXml = await backup.saveTaskXml(taskPath, taskName);
        backup.record('scheduledTask', item.target, <String, Object?>{'xmlFile': taskXml});
        try {
          await runPSCommand(
            "Unregister-ScheduledTask -TaskPath '$taskPath' -TaskName '$taskName' -Confirm:\$false",
            loggerInfoOutput: false,
          );
        } catch (_) {
          // Root tasks (`\Name`) and a few protected ones only answer to schtasks.
          final ProcessResult result = await Process.run('schtasks', <String>[
            '/delete',
            '/tn',
            '$taskPath$taskName',
            '/f',
          ]);
          if (result.exitCode != 0) {
            throw StateError('schtasks /delete failed: ${result.stderr}');
          }
        }
        return 'Unregistered';
      case OrphanKind.service:
        final String? serviceKey = await backup.exportRegistryKey(
          'HKLM',
          '$_servicesPath\\${item.target}',
        );
        backup.record('service', item.target, <String, Object?>{'regFile': serviceKey});
        final ProcessResult result = await Process.run('sc.exe', <String>['delete', item.target]);
        if (result.exitCode != 0) {
          logger.w('cleanup: sc delete failed for ${item.target}: ${result.stderr}');
          await WinRegistryService.deleteKey(LOCAL_MACHINE, '$_servicesPath\\${item.target}');
        }
        return 'Deleted';
    }
  }

  Future<String> _deleteStartupEntry(OrphanItem item, CleanupBackup backup) async {
    if (item.target.startsWith('HK')) return _deleteRegistryTarget(item, backup);
    final file = File(item.target);
    backup.record('startupFile', item.target);
    if (file.existsSync()) file.deleteSync();
    return 'Deleted';
  }

  Future<String> _deleteRegistryTarget(OrphanItem item, CleanupBackup backup) async {
    final ({BaseRegistryKey hive, String hiveName, String path, String? value})? reference =
        _registryRef(item.target);
    if (reference == null) throw StateError('Unsupported cleanup target: ${item.target}');
    final String? value = reference.value;
    final String? regFile = await backup.exportRegistryKey(reference.hiveName, reference.path);
    if (value != null) {
      backup.record('registryValue', item.target, <String, Object?>{'regFile': regFile});
      await WinRegistryService.deleteValue(reference.hive, reference.path, value);
      return 'Deleted';
    }
    backup.record('registryKey', item.target, <String, Object?>{'regFile': regFile});
    const userChoice = r'\UserChoice';
    if (reference.path.endsWith(userChoice)) {
      await _deleteUserChoice(
        reference.path.substring(0, reference.path.length - userChoice.length),
      );
      return 'Deleted protected key';
    }
    await WinRegistryService.deleteKey(reference.hive, reference.path);
    return 'Deleted';
  }

  /// Deletes a `UserChoice` key, which is protected against normal deletion.
  Future<void> _deleteUserChoice(String path) async {
    const script = r"""
$signature = @"
using System;
using System.Runtime.InteropServices;
public class UserChoiceRemover {
  [DllImport("advapi32.dll", SetLastError = true)]
  private static extern int RegOpenKeyEx(UIntPtr hKey, string subKey, int options, int rights, out UIntPtr result);
  [DllImport("advapi32.dll", SetLastError = true)]
  private static extern int RegDeleteKey(UIntPtr hKey, string subKey);
  public static void Remove(string subKey) {
    UIntPtr handle;
    RegOpenKeyEx((UIntPtr)0x80000001, subKey, 0, 0x20019, out handle);
    RegDeleteKey((UIntPtr)0x80000001, subKey);
  }
}
"@
Add-Type -TypeDefinition $signature
[UserChoiceRemover]::Remove('__PATH__')
""";
    await runPSCommand(script.replaceFirst('__PATH__', path), loggerInfoOutput: false);
  }

  /// Restores the changes of a previous run from its backup folder.
  ///
  /// Returns how many actions were restored.
  Future<int> restore(String backupPath) async {
    final manifest = File(p.join(backupPath, 'manifest.json'));
    if (!manifest.existsSync()) throw StateError('No manifest in $backupPath');
    final Object? decoded = jsonDecode(manifest.readAsStringSync());
    final List<Object?> actions = decoded is Map<String, Object?>
        ? (decoded['actions'] as List<Object?>? ?? const [])
        : const [];
    var restored = 0;
    for (final Map<String, Object?> action in actions.whereType<Map<String, Object?>>()) {
      if (await _restoreAction(action)) restored++;
    }
    return restored;
  }

  Future<bool> _restoreAction(Map<String, Object?> action) async {
    final target = action['target'] as String?;
    if (target == null) return false;
    try {
      switch (action['kind']) {
        case 'registryKey':
        case 'registryValue':
        case 'service':
          final regFile = action['regFile'] as String?;
          if (regFile == null || !File(regFile).existsSync()) return false;
          final ProcessResult result = await runPSCommand(
            'reg import "$regFile"',
            loggerInfoOutput: false,
          );
          return result.exitCode == 0;
        case 'folder':
          final quarantine = action['quarantine'] as String?;
          if (quarantine == null || !Directory(quarantine).existsSync()) return false;
          Directory(quarantine).renameSync(target);
          return true;
        case 'scheduledTask':
          final xmlFile = action['xmlFile'] as String?;
          if (xmlFile == null || !File(xmlFile).existsSync()) return false;
          final ProcessResult result = await runPSCommand(
            'schtasks /create /xml "$xmlFile" /tn "$target" /f',
            loggerInfoOutput: false,
          );
          return result.exitCode == 0;
        default:
          return false;
      }
    } catch (error) {
      logger.w('cleanup: could not restore $target', error: error);
      return false;
    }
  }
}
