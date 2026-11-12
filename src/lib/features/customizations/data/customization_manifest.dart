import '../domain/entities/customization_mod.dart';

/// The Windhawk mods MithenTool exposes, mirroring the user's Windhawk backup.
///
/// Settings are seeded into the engine at install time by
/// `installer/deploy-windhawk.ps1`; keep the two lists in sync.
const List<CustomizationMod> customizationManifest = [
  CustomizationMod(
    id: 'explorer-context-menu-classic',
    name: 'Mithen context menu',
    description:
        'Show the classic context menu inside the modern Windows 11 popup - rounded, borderless, no "Show more options"',
    group: CustomizationGroup.contextMenu,
    nativeNote: 'Overrides the native classic menu while enabled; turning it off returns to the native one',
  ),
  CustomizationMod(
    id: 'classic-menu-corners',
    name: 'Rounded classic menus',
    description: 'Round classic context menus and remove their 1px border',
    group: CustomizationGroup.contextMenu,
  ),
  CustomizationMod(
    id: 'taskbar-classic-menu',
    name: 'Taskbar classic context menu',
    description: 'Show the classic context menu when right-clicking taskbar items',
    group: CustomizationGroup.taskbar,
  ),
  CustomizationMod(
    id: 'explorer-frame-classic',
    name: 'Classic Explorer navigation bar',
    description: 'Restore the navigation bar Explorer had before the Windows 11 "Moments 4" update',
    group: CustomizationGroup.explorer,
  ),
  CustomizationMod(
    id: 'legacy-file-copy',
    name: 'Legacy file copy',
    description: 'Restore the Windows 7 file copy dialog',
    group: CustomizationGroup.explorer,
  ),
  CustomizationMod(
    id: 'modernize-folder-picker-dialog',
    name: 'Modern folder picker',
    description: 'Replace the classic "Browse for folder" dialog with the modern one',
    group: CustomizationGroup.explorer,
  ),
  CustomizationMod(
    id: 'taskbar-icon-size',
    name: 'Taskbar height and icon size',
    description: '40px taskbar with 17px icons, 35px buttons (16px / 32px when small)',
    group: CustomizationGroup.taskbar,
    nativeNote: 'MithenOS already sets the Windows small taskbar size',
  ),
  CustomizationMod(
    id: 'start-menu-size',
    name: 'Start menu size',
    description: '666 x 750 Start menu, search menu included',
    group: CustomizationGroup.start,
  ),
  CustomizationMod(
    id: 'windows-11-start-menu-styler',
    name: 'Start menu without Recommended',
    description: 'Hide the Recommended section from the Start menu',
    group: CustomizationGroup.start,
    nativeNote: 'MithenOS also hides it with a policy',
  ),
  CustomizationMod(
    id: 'pinned-only-on-start-menu',
    name: 'Pinned only Start menu',
    description: 'Hide the "All apps" and "Recommended" sections, leaving only your pins',
    group: CustomizationGroup.start,
    nativeNote: 'MithenOS already curates the pinned apps and hides recent items',
  ),
  CustomizationMod(
    id: 'windows-11-notification-center-styler',
    name: 'Hide notification center',
    description: 'Collapse the notification center panel so it no longer slides out',
    group: CustomizationGroup.notifications,
    nativeNote: 'MithenOS already turns notifications off',
  ),
];
