import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../extensions.dart';
import '../../features/cleanup/presentation/cleanup_page.dart';
import '../../features/home/home_page.dart';
import '../../features/ms_store/presentation/pages/ms_store_page.dart';
import '../../features/ms_store/presentation/pages/ms_store_product_page.dart';
import '../../features/system_monitor/presentation/system_monitor_page.dart';
import '../../features/tools/tools_page.dart';
import '../../features/tweaks/performance/performance_page.dart';
import '../../features/tweaks/personalization/personalization_page.dart';
import '../../features/tweaks/security/security_page.dart';
import '../../features/tweaks/tweaks_page.dart';
import '../../features/tweaks/updates/updates_page.dart';
import '../../features/tweaks/utilities/utilities_page.dart';
import '../../main.dart';
import '../settings/settings_page.dart';
import 'app_routes.dart';
import 'app_shell.dart';

part 'app_router.g.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialRoute ?? RouteMeta.home.path,
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return AppShell(shellContext: context, child: child);
        },
        routes: [
          GoRoute(
            path: RouteMeta.home.path,
            name: 'home',
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: RouteMeta.tweaks.path,
            name: 'tweaks',
            builder: (context, state) => const TweaksPage(),
            routes: [
              GoRoute(
                path: 'security',
                name: 'security',
                pageBuilder: (context, state) => AppRoutes.buildPageWithHorizontalTransition(
                  barrierColor: context.theme.scaffoldBackgroundColor,
                  state: state,
                  child: const SecurityPage(),
                ),
              ),
              GoRoute(
                path: 'performance',
                name: 'performance',
                pageBuilder: (context, state) => AppRoutes.buildPageWithHorizontalTransition(
                  barrierColor: context.theme.scaffoldBackgroundColor,
                  state: state,
                  child: const PerformancePage(),
                ),
              ),
              GoRoute(
                path: 'personalization',
                name: 'personalization',
                pageBuilder: (context, state) => AppRoutes.buildPageWithHorizontalTransition(
                  barrierColor: context.theme.scaffoldBackgroundColor,
                  state: state,
                  child: const PersonalizationPage(),
                ),
              ),
              GoRoute(
                path: 'utilities',
                name: 'utilities',
                pageBuilder: (context, state) => AppRoutes.buildPageWithHorizontalTransition(
                  barrierColor: context.theme.scaffoldBackgroundColor,
                  state: state,
                  child: const UtilitiesPage(),
                ),
              ),
              GoRoute(
                path: 'updates',
                name: 'updates',
                pageBuilder: (context, state) => AppRoutes.buildPageWithHorizontalTransition(
                  barrierColor: context.theme.scaffoldBackgroundColor,
                  state: state,
                  child: const UpdatesPage(),
                ),
              ),
            ],
          ),
          GoRoute(
            path: RouteMeta.msStore.path,
            name: 'msstore',
            builder: (context, state) => const MSStorePage(),
            routes: [
              GoRoute(
                path: 'product/:productId',
                name: 'msstore-product',
                pageBuilder: (context, state) {
                  // final SearchProduct? product = state.extra is SearchProduct
                  //     ? state.extra! as SearchProduct
                  //     : null;
                  final String productId = state.pathParameters['productId']!;

                  return AppRoutes.buildPageWithHorizontalTransition(
                    barrierColor: context.theme.scaffoldBackgroundColor,
                    state: state,
                    child: MSStoreProductPage(productId: productId),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: RouteMeta.systemMonitor.path,
            name: 'monitor',
            builder: (context, state) => const SystemMonitorPage(),
          ),
          GoRoute(
            path: RouteMeta.tools.path,
            name: 'tools',
            builder: (context, state) => const ToolsPage(),
          ),
          GoRoute(
            path: RouteMeta.cleanup.path,
            name: 'cleanup',
            builder: (context, state) => const CleanupPage(),
          ),
          GoRoute(
            path: RouteMeta.settings.path,
            name: 'settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );

  return router;
}
