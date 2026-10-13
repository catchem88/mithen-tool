import 'package:riverpod/riverpod.dart';

import 'data/mithen_apps.dart';
import 'data/tools_repository.dart';

/// Provides the [ToolsRepository].
final toolsRepositoryProvider = Provider<ToolsRepository>((ref) => const ToolsRepository());

/// Installation state per Mithen app name.
final mithenAppsInstalledProvider = FutureProvider<Map<String, bool>>(
  (ref) => ref
      .watch(toolsRepositoryProvider)
      .installedApps(mithenApps.map((MithenAppInfo app) => app.name)),
);

/// Whether the playbook association script is available on this system.
final playbookAssocScriptProvider = FutureProvider<bool>(
  (ref) => ref.watch(toolsRepositoryProvider).assocScript.existsSync(),
);
