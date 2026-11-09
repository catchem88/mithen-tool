import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:win32_registry/win32_registry.dart';

import '../../../core/cli_generator/annotations.dart';
import '../../../core/services/win_registry_service.dart';
import '../../../core/trusted_installer/trusted_installer_service.dart';

part 'utilities_service.g.dart';

@CliCommand(name: 'utilities', description: 'Utilities tweaks')
abstract class UtilitiesService() {
  @CliToggle(
    name: 'hibernation',
    status: 'statusHibernation',
    enable: 'enableHibernation',
    disable: 'disableHibernation',
  )
  bool get statusHibernation;
  Future<void> enableHibernation();
  Future<void> disableHibernation();

  @CliToggle(
    name: 'fast-startup',
    status: 'statusFastStartup',
    enable: 'enableFastStartup',
    disable: 'disableFastStartup',
  )
  bool get statusFastStartup;
  Future<void> enableFastStartup();
  Future<void> disableFastStartup();

  @CliToggle(
    name: 'modern-standby',
    status: 'statusModernStandby',
    enable: 'enableModernStandby',
    disable: 'disableModernStandby',
  )
  bool get statusModernStandby;
  Future<void> enableModernStandby();
  Future<void> disableModernStandby();

  @CliToggle(
    name: 'tm-monitoring',
    status: 'statusTMMonitoring',
    enable: 'enableTMMonitoring',
    disable: 'disableTMMonitoring',
  )
  bool get statusTMMonitoring;
  Future<void> enableTMMonitoring();
  Future<void> disableTMMonitoring();

  @CliToggle(
    name: 'standby-network',
    status: 'statusStandbyNetwork',
    enable: 'enableStandbyNetwork',
    disable: 'disableStandbyNetwork',
  )
  bool get statusStandbyNetwork;
  Future<void> enableStandbyNetwork();
  Future<void> disableStandbyNetwork();

  @CliToggle(
    name: 'open-in-terminal-admin',
    status: 'statusOpenInTerminalAdmin',
    enable: 'enableOpenInTerminalAdmin',
    disable: 'disableOpenInTerminalAdmin',
  )
  bool get statusOpenInTerminalAdmin;
  Future<void> enableOpenInTerminalAdmin();
  Future<void> disableOpenInTerminalAdmin();

  @CliToggle(
    name: 'usage-reporting',
    status: 'statusUsageReporting',
    enable: 'enableUsageReporting',
    disable: 'disableUsageReporting',
  )
  bool get statusUsageReporting;
  Future<void> enableUsageReporting();
  Future<void> disableUsageReporting();
}

class const UtilitiesServiceImpl() implements UtilitiesService {
  static const String _standbyNetworkPolicy =
      r'SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9';
  static const String _terminalAdminVerb =
      r'SOFTWARE\Classes\Directory\shell\OpenWTHereAsAdmin';
  static const String _terminalBackgroundAdminVerb =
      r'SOFTWARE\Classes\Directory\Background\shell\OpenWTHereAsAdmin';
  static const List<String> _terminalAdminVerbs = [
    _terminalAdminVerb,
    _terminalBackgroundAdminVerb,
  ];
  static const String _terminalAdminPowerShellCommand =
      r'''powershell.exe -WindowStyle Hidden "Start-Process -Verb RunAs powershell.exe -WorkingDirectory '%V\.'"''';

  /// Builds the elevated command for an installed Windows Terminal.
  ///
  /// The full package path is used instead of the `wt.exe` app execution alias:
  /// aliases are not resolvable from an elevated process, which makes
  /// `start wt.exe` fail with "Windows cannot find 'wt.exe'".
  static String _elevatedTerminalCommand(String wtPath) {
    return '''powershell.exe -WindowStyle Hidden "Start-Process -Verb RunAs -FilePath '$wtPath' -WorkingDirectory '%V\\.'"''';
  }

  /// Path to the installed Windows Terminal executable, or null when absent.
  static Future<String?> _windowsTerminalPath() async {
    final ProcessResult result = await runPSCommand(
      r'$pkg = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue | '
      r'Select-Object -First 1; if ($pkg) { Join-Path $pkg.InstallLocation "wt.exe" }',
      stdout: true,
      loggerInfoOutput: false,
    );
    final String path = result.stdout.toString().trim();
    if (path.isEmpty || !File(path).existsSync()) return null;
    return path;
  }

  /// Whether either power source refuses network connectivity during standby.
  static bool _isStandbyNetworkDisabled(BaseRegistryKey hive) {
    return WinRegistryService.readInt(hive, _standbyNetworkPolicy, 'ACSettingIndex') == 0 ||
        WinRegistryService.readInt(hive, _standbyNetworkPolicy, 'DCSettingIndex') == 0;
  }

  @override
  bool get statusHibernation {
    return WinRegistryService.readInt(
          LOCAL_MACHINE,
          r'SYSTEM\ControlSet001\Control\Power',
          'HibernateEnabled',
        ) ==
        1;
  }

  @override
  Future<void> enableHibernation() async {
    await Future.wait([
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'Software\Policies\Microsoft\Windows\System',
        'ShowHibernateOption',
        1,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Control\Power',
        'HibernateEnabled',
        1,
      ),
      shell.run(r'''
powercfg -h on
powercfg /h /type full
'''),
    ]);
  }

  @override
  Future<void> disableHibernation() async {
    await Future.wait([
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'Software\Policies\Microsoft\Windows\System',
        'ShowHibernateOption',
        0,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Control\Power',
        'HibernateEnabled',
        0,
      ),
      shell.run(r'''
powercfg -h off
'''),
    ]);
  }

  // int? get statusHibernationMode {
  //   return await WinRegistryService.readInt(LOCAL_MACHINE,
  //       r'System\ControlSet001\Control\Power', 'HiberFileType');
  // }

  // Future<void> setHibernateModeReduced() async {
  //   await shell.run('powercfg /h /type reduced');
  // }

  // Future<void> setHibernateModeFull() async {
  //   await shell.run('powercfg /h /type full');
  // }

  @override
  bool get statusFastStartup {
    return WinRegistryService.readInt(
          LOCAL_MACHINE,
          r'System\ControlSet001\Control\Session Manager\Power',
          'HiberbootEnabled',
        ) ==
        1;
  }

  @override
  Future<void> enableFastStartup() async {
    await Future.wait([
      enableHibernation(),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'System\ControlSet001\Control\Session Manager\Power',
        'HiberbootEnabled',
        1,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'Software\Policies\Microsoft\Windows\System',
        'HiberbootEnabled',
        1,
      ),
    ]);
  }

  @override
  Future<void> disableFastStartup() async {
    await Future.wait([
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'System\ControlSet001\Control\Session Manager\Power',
        'HiberbootEnabled',
        0,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'Software\Policies\Microsoft\Windows\System',
        'HiberbootEnabled',
        0,
      ),
    ]);
  }

  @override
  bool get statusModernStandby {
    return WinRegistryService.readInt(
          LOCAL_MACHINE,
          r'System\CurrentControlSet\Control\Power',
          'PlatformAoAcOverride',
        ) !=
        0;
  }

  @override
  Future<void> enableModernStandby() {
    return WinRegistryService.deleteValue(
      LOCAL_MACHINE,
      r'System\CurrentControlSet\Control\Power',
      'PlatformAoAcOverride',
    );
  }

  @override
  Future<void> disableModernStandby() {
    return WinRegistryService.writeRegistryValue(
      LOCAL_MACHINE,
      r'System\CurrentControlSet\Control\Power',
      'PlatformAoAcOverride',
      0,
    );
  }

  @override
  bool get statusStandbyNetwork {
    return !_isStandbyNetworkDisabled(LOCAL_MACHINE) && !_isStandbyNetworkDisabled(CURRENT_USER);
  }

  @override
  Future<void> enableStandbyNetwork() async {
    await Future.wait([
      for (final BaseRegistryKey hive in [LOCAL_MACHINE, CURRENT_USER]) ...[
        WinRegistryService.deleteValue(hive, _standbyNetworkPolicy, 'ACSettingIndex'),
        WinRegistryService.deleteValue(hive, _standbyNetworkPolicy, 'DCSettingIndex'),
      ],
    ]);
  }

  @override
  Future<void> disableStandbyNetwork() async {
    await Future.wait([
      for (final BaseRegistryKey hive in [LOCAL_MACHINE, CURRENT_USER]) ...[
        WinRegistryService.writeRegistryValue(hive, _standbyNetworkPolicy, 'ACSettingIndex', 0),
        WinRegistryService.writeRegistryValue(hive, _standbyNetworkPolicy, 'DCSettingIndex', 0),
      ],
    ]);
  }

  @override
  bool get statusOpenInTerminalAdmin {
    return WinRegistryService.readString(
          LOCAL_MACHINE,
          '$_terminalAdminVerb\\command',
          '',
        ) !=
        null;
  }

  @override
  Future<void> enableOpenInTerminalAdmin() async {
    final String? wtPath = await _windowsTerminalPath();
    final String command = wtPath == null
        ? _terminalAdminPowerShellCommand
        : _elevatedTerminalCommand(wtPath);

    for (final String verb in _terminalAdminVerbs) {
      await WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        verb,
        'MUIVerb',
        'Open in Terminal (Admin)',
      );
      await WinRegistryService.writeRegistryValue(LOCAL_MACHINE, verb, 'HasLUAShield', '');
      await WinRegistryService.deleteValue(LOCAL_MACHINE, verb, 'Extended');
      await WinRegistryService.writeRegistryValue(LOCAL_MACHINE, '$verb\\command', '', command);
    }
  }

  @override
  Future<void> disableOpenInTerminalAdmin() async {
    await Future.wait([
      for (final String verb in _terminalAdminVerbs)
        WinRegistryService.deleteKey(LOCAL_MACHINE, verb),
    ]);
  }

  @override
  bool get statusTMMonitoring {
    return WinRegistryService.readInt(
              LOCAL_MACHINE,
              r'SYSTEM\ControlSet001\Services\GraphicsPerfSvc',
              'Start',
            ) ==
            2 &&
        WinRegistryService.readInt(LOCAL_MACHINE, r'SYSTEM\ControlSet001\Services\Ndu', 'Start') ==
            2;
  }

  @override
  Future<void> enableTMMonitoring() async {
    await Future.wait([
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\GraphicsPerfSvc',
        'Start',
        2,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\Ndu',
        'Start',
        2,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\DPS',
        'Start',
        2,
      ),
    ]);
  }

  @override
  Future<void> disableTMMonitoring() async {
    await Future.wait([
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\GraphicsPerfSvc',
        'Start',
        4,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\Ndu',
        'Start',
        4,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\DPS',
        'Start',
        4,
      ),
    ]);
  }

  @override
  bool get statusUsageReporting {
    return WinRegistryService.readInt(
          LOCAL_MACHINE,
          r'SYSTEM\ControlSet001\Services\DPS',
          'Start',
        ) !=
        4;
  }

  @override
  Future<void> enableUsageReporting() async {
    await Future.wait([
      TrustedInstallerServiceImpl().executeCommand('wevtutil', [
        'sl',
        'Microsoft-Windows-SleepStudy/Diagnostic',
        '/q:true',
      ]),
      TrustedInstallerServiceImpl().executeCommand('wevtutil', [
        'sl',
        'Microsoft-Windows-Kernel-Processor-Power/Diagnostic',
        '/q:true',
      ]),
      TrustedInstallerServiceImpl().executeCommand('wevtutil', [
        'sl',
        'Microsoft-Windows-UserModePowerService/Diagnostic',
        '/q:true',
      ]),
      WinRegistryService.deleteValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Control\Session Manager\Power',
        'SleepStudyDisabled',
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\DPS',
        'Start',
        2,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\diagsvc',
        'Start',
        2,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\WdiServiceHost',
        'Start',
        2,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\WdiSystemHost',
        'Start',
        2,
      ),
    ]);
  }

  @override
  Future<void> disableUsageReporting() async {
    await Future.wait([
      TrustedInstallerServiceImpl().executeCommand('wevtutil', [
        'sl',
        'Microsoft-Windows-SleepStudy/Diagnostic',
        '/q:false',
      ]),
      TrustedInstallerServiceImpl().executeCommand('wevtutil', [
        'sl',
        'Microsoft-Windows-Kernel-Processor-Power/Diagnostic',
        '/q:false',
      ]),
      TrustedInstallerServiceImpl().executeCommand('wevtutil', [
        'sl',
        'Microsoft-Windows-UserModePowerService/Diagnostic',
        '/q:false',
      ]),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Control\Session Manager\Power',
        'SleepStudyDisabled',
        1,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\DPS',
        'Start',
        4,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\diagsvc',
        'Start',
        4,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\WdiServiceHost',
        'Start',
        4,
      ),
      WinRegistryService.writeRegistryValue(
        LOCAL_MACHINE,
        r'SYSTEM\ControlSet001\Services\WdiSystemHost',
        'Start',
        4,
      ),
    ]);
  }
}

@Riverpod(keepAlive: true)
UtilitiesService utilitiesService(Ref ref) {
  return const UtilitiesServiceImpl();
}

@riverpod
bool hibernationStatus(Ref ref) {
  return ref.watch(utilitiesServiceProvider).statusHibernation;
}

@riverpod
bool fastStartupStatus(Ref ref) {
  return ref.watch(utilitiesServiceProvider).statusFastStartup;
}

@riverpod
bool statusModernStandbyStatus(Ref ref) {
  return ref.watch(utilitiesServiceProvider).statusModernStandby;
}

@riverpod
bool tmMonitoringStatus(Ref ref) {
  return ref.watch(utilitiesServiceProvider).statusTMMonitoring;
}

@riverpod
bool standbyNetworkStatus(Ref ref) {
  return ref.watch(utilitiesServiceProvider).statusStandbyNetwork;
}

@riverpod
bool openInTerminalAdminStatus(Ref ref) {
  return ref.watch(utilitiesServiceProvider).statusOpenInTerminalAdmin;
}

@riverpod
bool usageReportingStatus(Ref ref) {
  return ref.watch(utilitiesServiceProvider).statusUsageReporting;
}
