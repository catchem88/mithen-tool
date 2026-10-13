import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as msicons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/card_highlight.dart';
import '../../core/widgets/loading_dialog.dart';
import '../../extensions.dart';
import '../../i18n/generated/strings.g.dart';
import '../../utils.dart';
import '../../utils_gui.dart';
import '../cleanup/presentation/cleanup_scan_dialog.dart';
import 'data/mithen_apps.dart';
import 'tools_providers.dart';

/// Microsoft Activation Scripts (MAS).
const String activationScriptsUrl = 'https://github.com/massgravel/Microsoft-Activation-Scripts';
const String activationCommand = 'irm https://get.activated.win | iex';

/// ChrisTitusTech WinUtil.
const String tweakToolUrl = 'https://github.com/ChrisTitusTech/winutil';
const String tweakCommand = 'irm https://christitus.com/win | iex';

/// Runs [command] in a new elevated PowerShell window.
///
/// The tool runs elevated (requireAdministrator manifest), so the child process
/// inherits the administrator token. `start` gives it its own console window,
/// which both scripts need because they are interactive.
Future<void> runInElevatedPowerShell(String command) async {
  try {
    await Process.run('cmd.exe', <String>[
      '/c',
      'start',
      '',
      'powershell.exe',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-NoExit',
      '-Command',
      command,
    ]);
  } catch (error) {
    logger.e('tools: failed to launch PowerShell', error: error);
  }
}

/// Maintenance tools and links to every Mithen app.
class const ToolsPage({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, bool>? installed = ref.watch(mithenAppsInstalledProvider).value;
    final bool scriptAvailable = ref.watch(playbookAssocScriptProvider).value ?? false;

    return ScaffoldPage.scrollable(
      padding: kScaffoldPagePadding,
      children: [
        CardHighlight(
          icon: msicons.FluentIcons.key_20_regular,
          label: t.toolsActivate,
          description: t.toolsActivateDescription,
          descriptionLink: activationScriptsUrl,
          action: Button(
            onPressed: () => runInElevatedPowerShell(activationCommand),
            child: Text(t.toolsRun),
          ),
        ),
        CardHighlight(
          icon: msicons.FluentIcons.developer_board_20_regular,
          label: t.toolsTweak,
          description: t.toolsTweakDescription,
          descriptionLink: tweakToolUrl,
          action: Button(
            onPressed: () => runInElevatedPowerShell(tweakCommand),
            child: Text(t.toolsRun),
          ),
        ),
        CardHighlight(
          icon: msicons.FluentIcons.broom_20_regular,
          label: t.toolsLeftovers,
          description: t.cleanupDescription,
          action: Button(
            onPressed: () => showCleanupScanDialog(context, ref),
            child: Text(t.toolsRun),
          ),
        ),
        CardHighlight(
          icon: msicons.FluentIcons.apps_20_regular,
          label: t.toolsMithenApps,
          description: t.toolsMithenAppsDescription,
          initiallyExpanded: true,
          children: [
            for (final MithenAppInfo app in mithenApps)
              _appTile(context, ref, app, installed, scriptAvailable),
          ],
        ),
      ].withSpacing(5),
    );
  }

  Widget _appTile(
    BuildContext context,
    WidgetRef ref,
    MithenAppInfo app,
    Map<String, bool>? installed,
    bool scriptAvailable,
  ) {
    final bool isInstalled = installed?[app.name] ?? false;
    return CardListTile(
      title: app.name,
      description: app.description,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: isInstalled ? t.toolsInstalled : t.toolsNotInstalled,
            child: Icon(
              isInstalled
                  ? msicons.FluentIcons.checkmark_circle_20_filled
                  : msicons.FluentIcons.dismiss_circle_20_regular,
              color: isInstalled ? Colors.green : null,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: scriptAvailable ? t.toolsReassociate : t.toolsReassociateUnavailable,
            child: Button(
              onPressed: isInstalled && scriptAvailable
                  ? () => _reassociate(context, ref, app)
                  : null,
              child: Text(t.toolsReassociate),
            ),
          ),
          const SizedBox(width: 8),
          Button(onPressed: () => launchURL(app.url), child: Text(t.toolsOpenGithub)),
        ],
      ),
    );
  }

  /// Re-applies the playbook file associations of [app] for the current user.
  Future<void> _reassociate(BuildContext context, WidgetRef ref, MithenAppInfo app) async {
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final Future<Object?> dialog = showLoadingDialog(
      context,
      t.toolsReassociate,
      message: t.toolsReassociateRunning,
    );
    Object? error;
    try {
      await ref.read(toolsRepositoryProvider).reassociate(app);
    } catch (e) {
      error = e;
      logger.e('tools: reassociate failed for ${app.name}', error: e);
    }
    if (navigator.canPop()) navigator.pop();
    await dialog;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) => ContentDialog(
        title: Text(error == null ? t.toolsReassociateDone : t.toolsReassociateFailed),
        content: Text(error?.toString() ?? t.toolsReassociateDone),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t.close)),
        ],
      ),
    );
  }
}
