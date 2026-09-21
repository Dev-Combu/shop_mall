import 'package:flutter/material.dart';
import 'package:shopmall/config/router/router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/config/theme/theme.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shopmall',
      theme: AppTheme.lightTheme, // 라이트 테마 적용
      routerConfig: router,
    );
  }
}
