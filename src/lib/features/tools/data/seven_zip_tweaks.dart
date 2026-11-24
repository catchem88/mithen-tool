import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';

import '../../../core/services/win_registry_service.dart';
import '../../../utils.dart';

/// Re-applies the MithenOS 7-Zip setup: archive associations, the Windows
/// zipped-folder icon and the six-item shell menu.
///
/// 7-Zip's own installer rewrites these on every update or reinstall.
final class const SevenZipTweaks() {
  static const String _tag = 'sevenzip:';
  static const String _progIdPrefix = '7-Zip';
  static const String _machineClasses = r'SOFTWARE\Classes';
  static const String _userClasses = r'SOFTWARE\Classes';
  static const String _optionsPath = r'SOFTWARE\7-Zip\Options';
  static const String _fileExtsPath =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts';

  /// Formats 7-Zip registers, minus `.iso`, which stays with Windows.
  static const List<String> extensions = <String>[
    '001',
    '7z',
    'apfs',
    'arj',
    'bz2',
    'bzip2',
    'cab',
    'cpio',
    'deb',
    'dmg',
    'esd',
    'fat',
    'gz',
    'gzip',
    'hfs',
    'lha',
    'lzh',
    'lzma',
    'ntfs',
    'rar',
    'rpm',
    'squashfs',
    'swm',
    'tar',
    'taz',
    'tbz',
    'tbz2',
    'tgz',
    'tpz',
    'txz',
    'tzst',
    'vhd',
    'vhdx',
    'wim',
    'xar',
    'xz',
    'z',
    'zip',
    'zst',
  ];

  /// Extract files, Extract Here, Extract to, Test archive, Add to archive, Add to .zip.
  static const int contextMenuOptions = 4375;

  static String get installDirectory =>
      p.join(Platform.environment['ProgramFiles'] ?? r'C:\Program Files', '7-Zip');

  static bool get isInstalled => File(p.join(installDirectory, '7zFM.exe')).existsSync();

  static String progId(String extension) => '$_progIdPrefix.$extension';

  /// The icon Windows uses for a compressed folder.
  static String get archiveIconPath =>
      p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32', 'zipfldr.dll');

  /// Applies the associations, icons and menu items for the machine and the current user.
  static Future<void> apply() async {
    if (!isInstalled) throw StateError('7-Zip is not installed');

    for (final String extension in extensions) {
      await _applyMachineAssociation(extension);
      _applyUserAssociation(extension);
    }

    await WinRegistryService.writeRegistryValue(
      CURRENT_USER,
      _optionsPath,
      'ContextMenu',
      contextMenuOptions,
    );
    await _removeStaleUserChoices();
    await _refreshShell();
  }

  static Future<void> _applyMachineAssociation(String extension) async {
    final String progId = SevenZipTweaks.progId(extension);
    final extensionPath = '$_machineClasses\\.$extension';
    final progIdPath = '$_machineClasses\\$progId';

    await WinRegistryService.writeRegistryValue(LOCAL_MACHINE, extensionPath, '', progId);
    await WinRegistryService.writeRegistryValue(
      LOCAL_MACHINE,
      '$extensionPath\\OpenWithProgIds',
      progId,
      '',
    );

    // Creating a ProgId stub without a command would break opening archives
    if (WinRegistryService.keyExists(LOCAL_MACHINE, progIdPath)) {
      await WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        '$progIdPath\\DefaultIcon',
        '',
        archiveIconPath,
      );
    }
  }

  static void _applyUserAssociation(String extension) {
    final String progId = SevenZipTweaks.progId(extension);
    final extensionPath = '$_userClasses\\.$extension';
    final progIdPath = '$_userClasses\\$progId';

    _setUserValue(extensionPath, '', progId);
    _setUserValue('$extensionPath\\OpenWithProgIds', progId, '');

    if (WinRegistryService.keyExists(CURRENT_USER, progIdPath)) {
      _setUserValue('$progIdPath\\DefaultIcon', '', archiveIconPath);
    }
  }

  static void _setUserValue(String path, String name, String value) {
    try {
      final RegistryKey key = WinRegistryService.currentUser.create(path);
      try {
        key.setValue(name, RegistryValue.string(value));
      } finally {
        key.close();
      }
    } catch (e) {
      logger.w('$_tag failed to write HKCU\\$path\\$name', error: e);
    }
  }

  /// Drops the protected `UserChoice` keys so the ProgIds above take effect.
  static Future<void> _removeStaleUserChoices() async {
    final paths = <String>[
      for (final String extension in extensions)
        if (WinRegistryService.keyExists(CURRENT_USER, '$_fileExtsPath\\.$extension\\UserChoice'))
          '$_fileExtsPath\\.$extension\\UserChoice',
    ];
    if (paths.isEmpty) return;

    try {
      await runPSCommand(_userChoiceScript(paths), loggerInfoOutput: false);
    } catch (e) {
      logger.w('$_tag could not clear UserChoice keys', error: e);
    }
  }

  static String _userChoiceScript(List<String> paths) {
    final String removals = paths
        .map((String path) => "[UserChoiceRemover]::Remove('$path')")
        .join('\n');
    return '''
\$signature = @"
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
Add-Type -TypeDefinition \$signature
$removals
''';
  }

  /// Makes Explorer re-read associations and icons without a restart.
  static Future<void> _refreshShell() async {
    const script = r'''
Add-Type -Namespace Shell -Name ChangeNotify -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);'
[Shell.ChangeNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
''';
    try {
      await runPSCommand(script, loggerInfoOutput: false);
    } catch (e) {
      logger.w('$_tag shell refresh failed', error: e);
    }
  }
}
