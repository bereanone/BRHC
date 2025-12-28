import 'package:flutter/material.dart';

import '../widgets/fade_route.dart';
import 'sections_screen.dart';

class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Bible Readings for the Home',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '1914 Edition',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 26),
              Text(
                '“But sanctify the Lord God in your hearts: and be ready always to give '
                'an answer to every man that asketh you a reason of the hope that is in '
                'you with meekness and fear.”',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '— 1 Peter 3:15 (KJV)',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 220,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      FadePageRoute<void>(page: const SectionsScreen()),
                    );
                  },
                  child: const Text(
                    'ENTER',
                    style: TextStyle(
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Image.asset(
                    'assets/images/Logo2.png',
                    height: 52,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
