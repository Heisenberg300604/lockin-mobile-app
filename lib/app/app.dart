/// The root widget: theme, router, and the Clerk wrapper.
library;

import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/data/clerk_auth_gateway.dart';
import 'router.dart';

/// LockIn.
class LockInApp extends ConsumerWidget {
  /// Creates the app.
  const LockInApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final gateway = ref.watch(authGatewayProvider).value;

    return MaterialApp.router(
      title: 'LockIn',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      builder: (context, child) {
        var content = child ?? const SizedBox.shrink();
        // Clerk's Google sign-in shows a web view through an overlay host that
        // `ClerkAuth` provides. We create Clerk's state ourselves (see
        // ClerkAuthGateway) and just hand it over here.
        if (gateway is ClerkAuthGateway) {
          content = ClerkAuth(authState: gateway.clerkState, child: content);
        }
        // Dark status-bar icons on the light cream backgrounds.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
          child: content,
        );
      },
    );
  }
}
