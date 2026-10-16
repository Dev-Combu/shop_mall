import 'package:flutter/material.dart';
import 'package:shopmall/config/router/router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shopmall/config/theme/theme.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('.env 파일 로드 실패 또는 미존재: $e');
  }
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
