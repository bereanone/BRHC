import 'package:flutter/material.dart';

import 'screens/launch_screen.dart';
import 'startup/startup_data_verification.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await verifyAndPrepareStartupData();
  runApp(const BrhcApp());
}

class BrhcApp extends StatelessWidget {
  const BrhcApp({super.key});

  @override
  Widget build(BuildContext context) {
    const parchment = Color(0xFFF3E7D3);
    const surface = Color(0xFFF7EEDF);
    const ink = Color(0xFF3E2F1C);
    const accent = Color(0xFF9C6B3E);

    final baseText = Typography.blackCupertino.apply(
      fontFamily: 'serif',
      bodyColor: ink,
      displayColor: ink,
    );

    return MaterialApp(
      title: 'Bible Readings for the Home Circle',
      onGenerateTitle: (context) {
        final width = MediaQuery.sizeOf(context).width;
        return width < 420
            ? 'Bible Readings for the Home'
            : 'Bible Readings for the Home Circle';
      },
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: parchment,
        colorScheme: const ColorScheme.light(
          primary: accent,
          secondary: accent,
          surface: surface,
          background: parchment,
          onPrimary: Color(0xFFF9F4EC),
          onSurface: ink,
          onBackground: ink,
        ),
        textTheme: baseText,
        appBarTheme: const AppBarTheme(
          backgroundColor: parchment,
          foregroundColor: ink,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'serif',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: const Color(0xFFF9F4EC),
            textStyle: const TextStyle(
              fontFamily: 'serif',
              fontWeight: FontWeight.w600,
            ),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: ink,
            textStyle: const TextStyle(fontFamily: 'serif'),
          ),
        ),
        dividerColor: ink.withOpacity(0.25),
      ),
      home: const LaunchScreen(),
    );
  }
}
