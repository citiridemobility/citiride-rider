import 'package:flutter/material.dart';

import '../core/firebase/firebase_bootstrap.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_store.dart';

class CitirideApp extends StatelessWidget {
  CitirideApp({super.key, required FirebaseStatus firebaseStatus})
    : _router = AppRouter.create();

  final RouterConfig<Object> _router;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: CitirideThemeModeStore.instance.mode,
      builder: (context, themeMode, _) {
        return MaterialApp.router(
          title: 'citiride',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          routerConfig: _router,
        );
      },
    );
  }
}
