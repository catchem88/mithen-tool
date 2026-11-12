/// One Windhawk mod exposed as a toggle on the Windows customizations page.
final class const CustomizationMod({
  /// Windhawk mod ID, also the CLI key and the registry subkey name.
  required final String id,

  /// Name shown in the UI (the mod's own catalog name).
  required final String name,

  /// One-line explanation shown under the title.
  required final String description,

  /// Group the row belongs to.
  required final CustomizationGroup group,

  /// Note shown when MithenOS already applies part of this natively.
  final String? nativeNote,
}) {
  /// Registry path of this mod's engine configuration.
  String get registryPath => 'SOFTWARE\\Windhawk\\Engine\\Mods\\$id';
}

/// Groups used to lay the toggles out in cards.
enum CustomizationGroup() {
  contextMenu,
  explorer,
  taskbar,
  start,
  notifications,
}
