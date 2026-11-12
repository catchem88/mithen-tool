import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

import '../../../core/services/win_registry_service.dart';
import '../../../utils.dart';
import '../domain/entities/customization_mod.dart';

/// Who owns the Windhawk engine on this machine.
enum WindhawkEngineState() {
  /// No engine present at all - the mini engine was never deployed.
  absent,

  /// MithenTool's bundled engine, recognised by its version sentinel.
  managed,

  /// A Windhawk the user installed themselves - the page stays read-only.
  external,
}

/// Drives the bundled Windhawk engine.
///
/// The engine is deployed by the installer; this service never installs or
/// updates anything, it only flips the per-mod `Disabled` flag and reports
/// state. Reading comes from the registry, mutations go through the bundled
/// `windhawk-cli.exe` so the engine is notified about the change.
final class const WindhawkService() {
  static const String _sentinelKey = r'SOFTWARE\MithenTool';
  static const String _sentinelName = 'WindhawkEngine';
  static const String _modsKey = r'SOFTWARE\Windhawk\Engine\Mods';
  static const String _sentinelKeyWow64 = r'SOFTWARE\WOW6432Node\MithenTool';
  static const String _classicContextMenuId = 'explorer-context-menu-classic';
  static const String _intentKey = r'SOFTWARE\MithenTool';
  static const String _intentName = 'ClassicContextMenu';
  static const String _newContextMenuClsid =
      r'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}';
  static const List<String> _uninstallKeys = [
    r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Windhawk',
    r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Windhawk',
  ];

  /// `<install dir>\windhawk-engine`, where the payload is installed.
  String get appRoot {
    final String installDir = File(Platform.resolvedExecutable).parent.path;
    return '$installDir\\windhawk-engine';
  }

  String get _executable => '$appRoot\\windhawk.exe';

  /// The bundled engine version, written to the sentinel by the installer.
  String get bundledVersion => '2.0.0-alpha.7';

  WindhawkEngineState get engineState {
    final String? sentinel = _sentinel;
    if (sentinel == 'skipped-external') return WindhawkEngineState.external;
    if (sentinel == bundledVersion) return WindhawkEngineState.managed;
    if (sentinel != null) return WindhawkEngineState.external;

    // No sentinel: only a genuine Windhawk (it always registers an uninstall
    // entry) counts as external. Our own payload can be present without a
    // sentinel if setup was interrupted - that is a "not registered" state,
    // not a foreign install.
    if (_hasUninstallEntry) return WindhawkEngineState.external;
    return WindhawkEngineState.absent;
  }

  /// The sentinel written by the deploy script, from both registry views.
  ///
  /// The script may run under 32-bit PowerShell, where `HKLM\SOFTWARE` is
  /// redirected to `WOW6432Node`; read both so a redirected write is not
  /// mistaken for a foreign installation.
  String? get _sentinel {
    for (final String path in [_sentinelKey, _sentinelKeyWow64]) {
      final String? value = WinRegistryService.readString(LOCAL_MACHINE, path, _sentinelName);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  bool get _hasUninstallEntry {
    for (final String path in _uninstallKeys) {
      if (WinRegistryService.readString(LOCAL_MACHINE, path, 'DisplayName') != null) return true;
    }
    return false;
  }

  /// Whether the bundled engine files are on disk but not registered yet.
  bool get needsRepair =>
      engineState == WindhawkEngineState.absent && File(_executable).existsSync();

  /// Re-runs the bundled deploy script to register the engine and its mods.
  Future<void> repair() async {
    final String installDir = File(Platform.resolvedExecutable).parent.path;
    final script = '$installDir\\windhawk\\deploy-windhawk.ps1';
    if (!File(script).existsSync()) {
      throw StateError('deploy-windhawk.ps1 is missing from $installDir\\windhawk');
    }

    final ProcessResult result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script,
      '-AppRoot',
      appRoot,
    ]);
    final String output = '${result.stdout}${result.stderr}'.trim();
    if (result.exitCode != 0) {
      logger.e('customizations: repair failed ($output)');
      throw ProcessException('powershell.exe', [script], output, result.exitCode);
    }
    logger.i('customizations: engine registered ($output)');
  }

  /// Registry key of [mod] as the engine actually registered it.
  ///
  /// The bundled CLI registers mods installed from a local source file under
  /// `local@<id>`, while an older install registered them under the bare id.
  /// Both have to resolve to the same toggle.
  String _modKey(CustomizationMod mod) {
    final local = '$_modsKey\\local@${mod.id}';
    if (WinRegistryService.readString(LOCAL_MACHINE, local, 'Version') != null) {
      return local;
    }
    final String plain = mod.registryPath;
    if (WinRegistryService.readString(LOCAL_MACHINE, plain, 'Version') != null) {
      return plain;
    }
    return plain;
  }

  /// Whether the mod is currently injected.
  bool isEnabled(CustomizationMod mod) {
    final int? disabled = WinRegistryService.readInt(
      LOCAL_MACHINE,
      _modKey(mod),
      'Disabled',
    );
    return disabled == 0;
  }

  /// Whether the mod is registered with the engine at all.
  bool isInstalled(CustomizationMod mod) {
    return WinRegistryService.readString(LOCAL_MACHINE, _modKey(mod), 'Version') != null;
  }

  /// Whether the user wants the classic context menu.
  ///
  /// MithenOS writes the registry override before MithenTool ever runs, so the
  /// registry is the fallback source of truth. Once a toggle is used we store
  /// the choice here, because the override has to be removed while "Mithen
  /// context menu" is enabled.
  bool get classicMenuIntent {
    final int? stored = WinRegistryService.readInt(LOCAL_MACHINE, _intentKey, _intentName);
    if (stored != null) return stored != 0;
    return _isNativeOverridePresent;
  }

  bool get _isNativeOverridePresent {
    return WinRegistryService.readString(
          WinRegistryService.currentUser,
          '$_newContextMenuClsid\\InprocServer32',
          '',
        ) !=
        null;
  }

  /// Stores the user's choice and applies it immediately.
  Future<void> setClassicMenuIntent(bool classic) async {
    await WinRegistryService.writeRegistryValue(
      LOCAL_MACHINE,
      _intentKey,
      _intentName,
      classic ? 1 : 0,
    );
    await applyClassicMenuState();
  }

  /// Writes or removes the native override so the stored intent is honoured.
  ///
  /// While "Mithen context menu" is enabled the override must be gone, otherwise
  /// Windows shows the legacy menu and the mod has nothing to style.
  Future<void> applyClassicMenuState() async {
    final bool modEnabled = _isEnabledById(_classicContextMenuId);
    if (classicMenuIntent && !modEnabled) {
      await WinRegistryService.writeRegistryValue(
        WinRegistryService.currentUser,
        '$_newContextMenuClsid\\InprocServer32',
        '',
        '',
      );
    } else {
      await WinRegistryService.deleteKey(
        WinRegistryService.currentUser,
        _newContextMenuClsid,
      );
    }
  }

  bool _isEnabledById(String id) {
    for (final key in ['$_modsKey\\local@$id', '$_modsKey\\$id']) {
      final int? disabled = WinRegistryService.readInt(LOCAL_MACHINE, key, 'Disabled');
      if (disabled != null) return disabled == 0;
    }
    return false;
  }

  /// Enables or disables [mod].
  ///
  /// The flag is written straight to the engine configuration and the service is
  /// restarted, which makes the engine re-read every mod and inject the new
  /// state into the next process it sees. This deliberately does not go through
  /// `windhawk-cli`: hand-registered mods are unknown to the CLI's own profile,
  /// which made toggling a silent no-op.
  Future<void> setEnabled(CustomizationMod mod, {required bool enabled}) async {
    if (engineState != WindhawkEngineState.managed) {
      throw StateError('The customizations engine is not managed by MithenTool');
    }

    await WinRegistryService.writeRegistryValue(
      LOCAL_MACHINE,
      _modKey(mod),
      'Disabled',
      enabled ? 0 : 1,
    );
    if (mod.id == _classicContextMenuId) {
      await applyClassicMenuState();
    }
    await restartEngine();

    if (isEnabled(mod) != enabled) {
      throw StateError('The engine did not accept the change for ${mod.id}');
    }
    logger.i('customizations: ${mod.id} -> ${enabled ? "enabled" : "disabled"}');
  }

  /// Enables or disables every customization at once and manages the engine.
  ///
  /// Turning it off also stops the Windhawk service and sets it to disabled, so
  /// nothing keeps running in the background.
  Future<void> setAllEnabled(List<CustomizationMod> mods, {required bool enabled}) async {
    if (engineState != WindhawkEngineState.managed) {
      throw StateError('The customizations engine is not managed by MithenTool');
    }

    for (final mod in mods) {
      await WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        _modKey(mod),
        'Disabled',
        enabled ? 0 : 1,
      );
      if (mod.id == _classicContextMenuId) {
        await applyClassicMenuState();
      }
    }

    if (enabled) {
      await _setServiceStartup('auto');
      await restartEngine();
    } else {
      await _setServiceStartup('disabled');
      await _stopService();
    }
    logger.i('customizations: all mods ${enabled ? "enabled" : "disabled"}');
  }

  /// Whether the engine is running and every mod is enabled.
  Future<bool> isAllEnabled(List<CustomizationMod> mods) async {
    final (bool installed, bool running) = await serviceStatus();
    if (!installed || !running) return false;
    for (final mod in mods) {
      if (!isEnabled(mod)) return false;
    }
    return true;
  }

  Future<void> _setServiceStartup(String mode) async {
    final ProcessResult result = await Process.run('sc.exe', [
      'config',
      'Windhawk',
      'start=',
      mode,
    ]);
    if (result.exitCode != 0) {
      logger.w('customizations: sc config failed: ${result.stderr}');
    }
  }

  Future<void> _stopService() async {
    await Process.run('sc.exe', ['stop', 'Windhawk']);
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  /// Whether the Windhawk service is installed, and whether it is running.
  Future<(bool installed, bool running)> serviceStatus() async {
    try {
      final ProcessResult result = await Process.run('sc.exe', ['query', 'Windhawk']);
      final output = '${result.stdout}${result.stderr}';
      if (result.exitCode != 0 || output.contains('1060')) return (false, false);
      return (true, output.contains('RUNNING'));
    } catch (error) {
      logger.w('customizations: service query failed', error: error);
      return (false, false);
    }
  }

  /// Collects everything needed to tell why a mod is not applying.
  Future<String> diagnostics(List<CustomizationMod> mods) async {
    final out = StringBuffer();
    out.writeln('engine state : ${engineState.name}');
    out.writeln('engine path  : $appRoot');
    out.writeln('windhawk.exe : ${File(_executable).existsSync()}');

    final (bool installed, bool running) = await serviceStatus();
    out.writeln('service      : installed=$installed running=$running');
    final ProcessResult serviceConfig = await Process.run('sc.exe', ['qc', 'Windhawk']);
    out.writeln('service cfg  : ${serviceConfig.stdout.toString().trim()}');

    final String programData = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    for (final mod in mods) {
      final String key = _modKey(mod);
      final String? version = WinRegistryService.readString(
        LOCAL_MACHINE,
        key,
        'Version',
      );
      final String? dll = WinRegistryService.readString(
        LOCAL_MACHINE,
        key,
        'LibraryFileName',
      );
      final bool dllPresent =
          dll != null && File('$programData\\Windhawk\\Engine\\Mods\\64\\$dll').existsSync();
      out.writeln(
        '${mod.id.padRight(36)} v=${version ?? "-"} dll=$dllPresent enabled=${isEnabled(mod)}',
      );
    }

    final ProcessResult modules = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      r"(Get-Process explorer -ErrorAction SilentlyContinue).Modules | Where-Object { $_.FileName -match 'windhawk|context-menu-classic|taskbar-icon-size|start-menu-styler|notification-center' } | Select-Object -ExpandProperty FileName",
    ]);
    final String loaded = modules.stdout.toString().trim();
    out.writeln('explorer mods: ${loaded.isEmpty ? "<none injected>" : loaded}');

    final cli = File('$appRoot\\windhawk-cli.exe');
    if (cli.existsSync()) {
      final ProcessResult engineView = await Process.run(cli.path, ['mod', 'list', '--json']);
      final String view = engineView.stdout.toString().trim();
      if (view.isNotEmpty) {
        out.writeln('engine view  : ${view.length > 1500 ? view.substring(0, 1500) : view}');
      }
    }

    final dataDir = Directory('$programData\\Windhawk');
    if (dataDir.existsSync()) {
      final List<File> logs =
          dataDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((File file) => file.path.toLowerCase().endsWith('.log'))
              .where((File file) => !file.path.contains('UIData'))
              .toList()
            ..sort(
              (File a, File b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
            );
      for (final File log in logs.take(3)) {
        final List<String> lines = log.readAsLinesSync();
        final String tail = lines.skip(lines.length > 25 ? lines.length - 25 : 0).join('\n');
        out.writeln('log ${log.path}:\n$tail');
      }
    }

    for (final relative in [
      r'Windhawk\Engine\warning.txt',
      r'Windhawk\Engine\Mods\64',
    ]) {
      final path = '$programData\\$relative';
      out.writeln('$path : ${FileSystemEntity.typeSync(path)}');
    }

    return out.toString();
  }

  /// Restarts Explorer so a change becomes visible right away.
  Future<void> restartExplorer() async {
    await Process.run('taskkill.exe', ['/im', 'explorer.exe', '/f']);
    await Process.run('explorer.exe', [], runInShell: true);
  }

  /// Restarts the engine service so it re-reads the mod configuration.
  Future<void> restartEngine() async {
    await Process.run('sc.exe', ['stop', 'Windhawk']);
    await Future<void>.delayed(const Duration(seconds: 2));
    final ProcessResult start = await Process.run('sc.exe', ['start', 'Windhawk']);
    if (start.exitCode != 0) {
      logger.w('customizations: service start failed: ${start.stderr}');
    }
  }
}
