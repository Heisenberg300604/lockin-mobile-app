/// All screens and how they connect (go_router).
///
/// ## Route map
///
/// ```text
/// /splash                       while the auth SDK starts
/// /sign-in   /sign-up           signed-out only
/// /reset-password               reachable while signed out
/// ── signed in ──────────────────────────────────────────────
/// /                             Focus tab        ┐
/// /history?date=yyyy-MM-dd      History tab      │ bottom tabs (StatefulShellRoute)
/// /settings                     Settings tab     ┘
/// /tracking                     full "today" list
/// /commitments?path=&status=    full Build/Quit list
/// /commitment/new               creation wizard
/// /commitment/:id               detail  (?date= &locked=1)
/// /commitment/:id/reflect       reflection + restart
/// ```
///
/// Routes outside the tab shell open *on top of* it, so the tab bar is hidden
/// on focused screens (wizard, detail), as the design specifies.
///
/// ## Redirects
///
/// A single `redirect` function is the "guard": it looks at the session and
/// sends you to the right place. Screens never decide this themselves.
library;

import 'package:flutter/material.dart' show CircularProgressIndicator, MaterialPage, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/motion/reduced_motion.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/commitments/presentation/screens/commitment_detail_screen.dart';
import '../features/commitments/presentation/screens/commitments_list_screen.dart';
import '../features/commitments/presentation/screens/create_commitment_screen.dart';
import '../features/commitments/presentation/screens/focus_screen.dart';
import '../features/commitments/presentation/screens/history_screen.dart';
import '../features/commitments/presentation/screens/reflection_screen.dart';
import '../features/commitments/presentation/screens/tracking_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'tab_shell.dart';

/// The app's router.
final routerProvider = Provider<GoRouter>((ref) {
  // go_router re-runs `redirect` whenever this notifier fires.
  final sessionChanges = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => sessionChanges.value++);
  ref.onDispose(sessionChanges.dispose);

  // With "reduce motion" on, screens appear instantly.
  Page<void> page(GoRouterState state, Widget child) => ref.read(reducedMotionProvider)
      ? NoTransitionPage<void>(key: state.pageKey, child: child)
      : MaterialPage<void>(key: state.pageKey, child: child);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: sessionChanges,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      final isAuthRoute = location == '/sign-in' || location == '/sign-up';

      if (session.loading) return location == '/splash' ? null : '/splash';
      if (session.identity == null) {
        // Signed out: only the auth screens are available.
        return isAuthRoute || location == '/reset-password' ? null : '/sign-in';
      }
      // Signed in: leave the auth screens and splash behind.
      return isAuthRoute || location == '/splash' ? '/' : null;
    },
    routes: [
      GoRoute(path: '/splash', pageBuilder: (c, s) => page(s, const _Splash())),
      GoRoute(path: '/sign-in', pageBuilder: (c, s) => page(s, const AuthScreen())),
      GoRoute(path: '/sign-up', pageBuilder: (c, s) => page(s, const AuthScreen(signUp: true))),
      GoRoute(path: '/reset-password', pageBuilder: (c, s) => page(s, const ResetPasswordScreen())),

      // Bottom tabs. Each branch keeps its own navigation stack and scroll.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => TabShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (c, s) => const FocusScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/history',
              builder: (c, s) => HistoryScreen(initialDate: s.uri.queryParameters['date']),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
          ]),
        ],
      ),

      GoRoute(path: '/tracking', pageBuilder: (c, s) => page(s, const TrackingScreen())),
      GoRoute(
        path: '/commitments',
        pageBuilder: (c, s) => page(
          s,
          CommitmentsListScreen(
            path: s.uri.queryParameters['path'],
            status: s.uri.queryParameters['status'],
          ),
        ),
      ),
      // `new` must come before `:id`, otherwise "new" would be read as an id.
      GoRoute(path: '/commitment/new', pageBuilder: (c, s) => page(s, const CreateCommitmentScreen())),
      GoRoute(
        path: '/commitment/:id',
        pageBuilder: (c, s) => page(
          s,
          CommitmentDetailScreen(
            id: s.pathParameters['id']!,
            requestedDate: s.uri.queryParameters['date'],
            justLocked: s.uri.queryParameters['locked'] == '1',
          ),
        ),
        routes: [
          GoRoute(
            path: 'reflect',
            pageBuilder: (c, s) => page(s, ReflectionScreen(id: s.pathParameters['id']!)),
          ),
        ],
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.canvasSetup,
        body: Center(child: CircularProgressIndicator(color: AppColors.inkPrimary)),
      );
}
