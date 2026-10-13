import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:riverpod/riverpod.dart';

import 'core/services/win_registry_command.dart';
import 'core/services/win_registry_service.dart';
import 'features/appx/appx.dart';
import 'features/cleanup/presentation/cleanup_command.dart';
import 'features/ms_store/domain/services/store_service.dart';
import 'features/ms_store/presentation/commands/ms_store_command.dart';
import 'features/system_monitor/presentation/system_monitor_command.dart';
import 'features/tweaks/tweaks_command.dart';
import 'features/winsxs/winsxs.dart';
import 'utils.dart';

Future<void> main(List<String> args) async {
  if (!WinRegistryService.isSupported) {
    logger.w(
      'Unsupported build detected. MithenTool is made for MithenOS - continuing, '
      'but some features may not work on this Windows installation',
    );
  }

  if (args.isEmpty) {
    final guiPath = "${mainPath.substring(0, mainPath.lastIndexOf(r"\"))}\\mithentoolw.exe";
    if (File(guiPath).existsSync()) {
      await Process.start('mithentoolw', []);
      exit(0);
    }
    exit(1);
  }
  const tag = 'cli_main:';

  final container = ProviderContainer();

  logger.i('$tag MithenTool CLI is starting');

  final runner =
      CommandRunner<void>(
          'mithentool',
          "MithenTool CLI v${const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0')}",
        )
        ..addCommand(AppxCommand(container: container))
        ..addCommand(MSStoreCommand(service: container.read(storeServiceProvider)))
        ..addCommand(WinRegistryServiceCliCommand(const WinRegistryCliService()))
        ..addCommand(TweaksCommand(container: container))
        ..addCommand(SystemMonitorCommand(container: container))
        ..addCommand(CleanupCommand())
        ..addCommand(WindowsPackageCommand(container: container));
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    logger.e('cli: ${e.message}');
    exit(appxExitUsage);
  }
  exit(0);
}
