import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

import '../../../core/services/win_registry_service.dart';
import '../../../utils.dart';
import 'mithen_apps.dart';

/// Installation state and playbook association actions for the Mithen apps.
final class const ToolsRepository() {
  static const List<String> _uninstallRoots = [
    r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
  ];

  /// The playbook script that applies file associations for a user hive.
  File get assocScript =>
      File('${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\Setup\\Scripts\\assoc.ps1');

  /// True per app name when an Add/Remove Programs entry starts with it.
  Map<String, bool> installedApps(Iterable<String> names) {
    final displayNames = <String>{};
    for (final BaseRegistryKey hive in [LOCAL_MACHINE, CURRENT_USER]) {
      for (final String root in _uninstallRoots) {
        for (final String sub in _subKeys(hive, root)) {
          final String? name = _displayName(hive, '$root\\$sub');
          if (name != null && name.isNotEmpty) displayNames.add(name);
        }
      }
    }
    return <String, bool>{
      for (final String name in names)
        name: displayNames.any((String display) => display.startsWith(name)),
    };
  }

  /// Re-applies the playbook file associations of [app] for the current user.
  Future<void> reassociate(MithenAppInfo app) async {
    final File script = assocScript;
    if (!script.existsSync()) {
      throw StateError('The MithenOS playbook files were not found on this system');
    }
    final ProcessResult result = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      'Placeholder',
      WinRegistryService.currentUserSid,
      for (final (String extension, String progId) in app.associations) '$extension:$progId',
    ]);
    if (result.exitCode != 0) {
      logger.e('tools: assoc.ps1 failed (${result.exitCode}): ${result.stderr}');
      throw StateError('assoc.ps1 exited with code ${result.exitCode}');
    }
  }

  String? _displayName(BaseRegistryKey hive, String path) {
    try {
      final RegistryKey key = hive.open(path);
      try {
        return key.getString('DisplayName');
      } finally {
        key.close();
      }
    } catch (_) {
      return null;
    }
  }

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
}
