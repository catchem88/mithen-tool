import 'package:fluent_ui/fluent_ui.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart' as msicons;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win32_registry/win32_registry.dart';

import '../../extensions.dart';
import '../../i18n/generated/strings.g.dart';
import '../../utils_gui.dart';
import '../services/win_registry_service.dart';
import '../widgets/app_icon_image.dart';
import '../widgets/card_highlight.dart';
import 'app_settings_provider.dart';
import 'locale_config.dart';

final List<ComboBoxItem<String>> languageList = AppLocale.values
    .map(
      (locale) => ComboBoxItem(
        value: locale.name,
        child: Text(LocaleConfig.languageNames[locale.name] ?? locale.name),
      ),
    )
    .toList();

class const SettingsPage({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScaffoldPage.scrollable(
      padding: kScaffoldPagePadding,
      children: const [
        _ThemeModeCard(),
        _ExperimentalCard(),
        _LanguageCard(),
        _AboutCard(),
        _GetHelpLink(),
      ].withSpacing(5),
    );
  }
}

class const _ThemeModeCard() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings appSettings = ref.watch(appSettingsProvider);

    return CardHighlight(
      icon: msicons.FluentIcons.paint_brush_20_regular,
      label: t.settingsCT,
      description: t.settingsCTDescription,
      action: ComboBox<ThemeMode>(
        value: appSettings.themeMode,
        onChanged: ref.read(appSettingsProvider.notifier).updateThemeMode,
        items: [
          .new(value: .system, child: Text(ThemeMode.system.name.uppercaseFirst())),
          .new(value: .light, child: Text(ThemeMode.light.name.uppercaseFirst())),
          .new(value: .dark, child: Text(ThemeMode.dark.name.uppercaseFirst())),
        ],
      ),
    );
  }
}

class const _ExperimentalCard() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool status = ref.watch(settingsExperimentalStatus);
    ref.watch(appSettingsProvider);

    return CardHighlight(
      icon: msicons.FluentIcons.warning_20_regular,
      label: t.settingsEPT,
      // description: t.settingsEPTDescription,
      action: CardToggleSwitch(
        value: status,
        onChanged: (value) async {
          await WinRegistryService.writeRegistryValue(
            LOCAL_MACHINE,
            r'SOFTWARE\Mithen\Mithen-Tool',
            'Experimental',
            value ? 1 : 0,
          );
          ref.invalidate(settingsExperimentalStatus);
        },
      ),
    );
  }
}

class const _LanguageCard() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardHighlight(
      icon: msicons.FluentIcons.local_language_20_regular,
      label: t.settingsLanguage,
      description: t.settingsLanguageDescription,
      action: ComboBox(
        value: TranslationProvider.of(context).locale.name,
        onChanged: (value) async {
          final String localeName = value ?? AppLocale.en.name;
          await WinRegistryService.writeRegistryValue(
            LOCAL_MACHINE,
            r'SOFTWARE\Mithen\Mithen-Tool',
            'Language',
            localeName,
          );
          ref.read(appSettingsProvider.notifier).updateLocale(localeName);
        },
        items: languageList,
      ),
    );
  }
}

class const _AboutCard() extends StatelessWidget {
  static const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  @override
  Widget build(BuildContext context) {
    return CardHighlight(
      leading: const AppIconImage(
        size: 24.0,
        fallback: Icon(msicons.FluentIcons.info_20_regular, size: 24),
      ),
      label: t.settingsAbout,
      description: 'MithenTool ${kDebugMode ? '(Debug)' : 'v$_appVersion'}',
    );
  }
}

final class const _GetHelpLink() extends StatelessWidget {
  static const _discordUrl = 'https://github.com/catchem88/mithen-os/issues';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: .centerLeft,
      child: Tooltip(
        useMousePosition: false,
        message: _discordUrl,
        child: HyperlinkButton(
          child: Text(t.settingsGetHelp),
          onPressed: () async => launchURL(_discordUrl),
        ),
      ),
    );
  }
}
