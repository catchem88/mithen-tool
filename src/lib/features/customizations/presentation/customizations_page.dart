import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as msicons;

import '../../../core/widgets/card_highlight.dart';
import '../../../extensions.dart';
import '../../../i18n/generated/strings.g.dart';
import '../../../utils.dart';
import '../../../utils_gui.dart';
import '../data/customization_manifest.dart';
import '../data/windhawk_service.dart';
import '../domain/entities/customization_mod.dart';

/// Extra Windows customizations, applied by the bundled offline Windhawk engine.
class const CustomizationsPage({super.key}) extends StatefulWidget {
  @override
  State<CustomizationsPage> createState() => _CustomizationsPageState();
}

class _CustomizationsPageState() extends State<CustomizationsPage> {
  static const WindhawkService _service = WindhawkService();

  WindhawkEngineState _engine = WindhawkEngineState.absent;
  final Map<String, bool> _enabled = {};
  bool _busy = false;
  bool _serviceRunning = false;
  bool _serviceInstalled = false;
  bool _masterOn = false;
  bool _autoRepairTried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final WindhawkEngineState engine = _service.engineState;

    // An interrupted setup leaves the engine files on disk without the
    // sentinel. Repair it on open instead of asking the user to press a
    // button; retry at most once per page visit so a broken install cannot
    // loop.
    if (engine == WindhawkEngineState.absent && _service.needsRepair && !_autoRepairTried) {
      _autoRepairTried = true;
      setState(() => _busy = true);
      try {
        await _service.repair();
      } catch (error) {
        logger.e('customizations: automatic repair failed', error: error);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
      await _load();
      return;
    }

    var installed = false;
    var running = false;
    var master = false;
    if (engine == WindhawkEngineState.managed) {
      final (bool isInstalled, bool isRunning) = await _service.serviceStatus();
      installed = isInstalled;
      running = isRunning;
      master = await _service.isAllEnabled(customizationManifest);
    }
    if (!mounted) return;

    setState(() {
      _engine = engine;
      _serviceInstalled = installed;
      _serviceRunning = running;
      _masterOn = master;
      for (final CustomizationMod mod in customizationManifest) {
        _enabled[mod.id] = _service.isEnabled(mod);
      }
    });
  }

  Future<void> _toggle(CustomizationMod mod, bool value) async {
    setState(() => _busy = true);
    try {
      await _service.setEnabled(mod, enabled: value);
      await _service.restartExplorer();
    } catch (error) {
      logger.e('customizations: failed to ${value ? "enable" : "disable"} ${mod.id}', error: error);
      if (mounted) await _showError(mod.name, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      padding: kScaffoldPagePadding,
      children: [_engineCard(), ..._groupCards()].withSpacing(5),
    );
  }

  Widget _engineCard() {
    final bool repairable = _service.needsRepair;
    final engineManaged = _engine == WindhawkEngineState.managed;
    final String serviceState = _serviceRunning
        ? t.customizationsServiceRunning
        : _serviceInstalled
        ? t.customizationsServiceStopped
        : t.customizationsServiceMissing;
    final (String title, String description, IconData icon) = switch (_engine) {
      WindhawkEngineState.managed => (
        t.customizationsEngineManaged,
        '${t.customizationsEngineManagedDescription} - $serviceState',
        msicons.FluentIcons.window_20_regular,
      ),
      WindhawkEngineState.external => (
        t.customizationsEngineExternal,
        t.customizationsEngineExternalDescription,
        msicons.FluentIcons.warning_20_regular,
      ),
      WindhawkEngineState.absent => (
        repairable ? t.customizationsEngineUnregistered : t.customizationsEngineAbsent,
        repairable
            ? t.customizationsEngineUnregisteredDescription
            : t.customizationsEngineAbsentDescription,
        msicons.FluentIcons.error_circle_20_regular,
      ),
    };

    final Widget? master = engineManaged
        ? CardToggleSwitch(
            value: _masterOn,
            enabled: !_busy,
            onChanged: _setAll,
          )
        : null;

    return CardHighlight(
      icon: icon,
      label: t.pageCustomizations,
      description: '$title - $description',
      action: master == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                master,
                const SizedBox(width: 10),
                Button(
                  onPressed: _busy ? null : _diagnose,
                  child: Text(t.customizationsDiagnose),
                ),
              ],
            ),
    );
  }

  Future<void> _diagnose() async {
    setState(() => _busy = true);
    try {
      final String report = await _service.diagnostics(customizationManifest);
      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => ContentDialog(
          title: Text(t.customizationsDiagnose),
          content: SelectableText(
            report,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          ),
          actions: [Button(onPressed: () => Navigator.pop(context), child: Text(t.okButton))],
        ),
      );
    } catch (error) {
      logger.e('customizations: diagnostics failed', error: error);
      if (mounted) await _showError(t.customizationsDiagnose, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAll(bool enabled) async {
    setState(() => _busy = true);
    try {
      // Enabling is the user's explicit "make it work" action, so repair an
      // unregistered-but-present engine first rather than requiring a click
      // on a separate button.
      if (enabled &&
          _service.engineState == WindhawkEngineState.absent &&
          _service.needsRepair) {
        await _service.repair();
      }
      await _service.setAllEnabled(customizationManifest, enabled: enabled);
      await _service.restartExplorer();
    } catch (error) {
      logger.e('customizations: master switch failed', error: error);
      if (mounted) await _showError(t.pageCustomizations, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  Future<void> _showError(String title, Object error) async {
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => ContentDialog(
        title: Text(title),
        content: Text('$error'),
        actions: [Button(onPressed: () => Navigator.pop(context), child: Text(t.okButton))],
      ),
    );
  }

  List<Widget> _groupCards() {
    final bool active = _engine == WindhawkEngineState.managed && _masterOn;
    final List<Widget> cards = [];
    for (final CustomizationGroup group in CustomizationGroup.values) {
      final List<CustomizationMod> mods = customizationManifest
          .where((CustomizationMod mod) => mod.group == group)
          .toList(growable: false);
      if (mods.isEmpty) continue;

      final int on = mods.where((CustomizationMod mod) => _enabled[mod.id] ?? false).length;
      cards.add(
        CardHighlight(
          icon: _groupIcon(group),
          label: _groupLabel(group),
          description: '$on/${mods.length}',
          children: [
            for (final CustomizationMod mod in mods)
              CardListTile(
                title: mod.name,
                description: mod.nativeNote == null
                    ? mod.description
                    : '${mod.description} - ${mod.nativeNote}',
                trailing: CardToggleSwitch(
                  value: _enabled[mod.id] ?? false,
                  enabled: active && !_busy,
                  onChanged: (bool value) => _toggle(mod, value),
                ),
              ),
          ],
        ),
      );
    }
    return cards;
  }

  IconData _groupIcon(CustomizationGroup group) => switch (group) {
    CustomizationGroup.contextMenu => msicons.FluentIcons.apps_20_regular,
    CustomizationGroup.explorer => msicons.FluentIcons.folder_20_regular,
    CustomizationGroup.taskbar => msicons.FluentIcons.window_20_regular,
    CustomizationGroup.start => msicons.FluentIcons.grid_20_regular,
    CustomizationGroup.notifications => msicons.FluentIcons.alert_20_regular,
  };

  String _groupLabel(CustomizationGroup group) => switch (group) {
    CustomizationGroup.contextMenu => t.customizationsGroupContextMenu,
    CustomizationGroup.explorer => t.customizationsGroupExplorer,
    CustomizationGroup.taskbar => t.customizationsGroupTaskbar,
    CustomizationGroup.start => t.customizationsGroupStart,
    CustomizationGroup.notifications => t.customizationsGroupNotifications,
  };
}
