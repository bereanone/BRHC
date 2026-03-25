import 'package:flutter/material.dart';

import '../support/donation_screen.dart';
import '../support/donation_service.dart';
import '../widgets/fade_route.dart';
import 'font_settings_screen.dart';
import 'how_to_use_screen.dart';
import 'sections_screen.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> {
  @override
  void initState() {
    super.initState();
    DonationService.instance.ensureStarted();
    DonationService.instance.recordLaunch();
  }

  Future<void> _openSupportScreen() async {
    await Navigator.of(context).push(
      FadePageRoute<void>(page: const DonationScreen()),
    );
  }

  Future<void> _handleEnter() async {
    final shouldPrompt = await DonationService.instance.shouldPrompt();
    if (!mounted) return;

    if (shouldPrompt) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Support Biblical Heritage?'),
          content: const Text(
            'Bible Readings for the Home is intended to remain free. If God has blessed you and you want to support this work, your gift helps make wider translation possible and helps carry the gospel to more lost souls through the app store.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('support'),
              child: const Text('Support'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('enter'),
              child: const Text('Enter now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('dismiss'),
              child: const Text('Don’t remind me'),
            ),
          ],
        ),
      );

      if (!mounted || choice == null) return;

      if (choice == 'support') {
        await DonationService.instance.markNotNow();
        if (!mounted) return;
        await _openSupportScreen();
        if (!mounted) return;
      } else if (choice == 'dismiss') {
        await DonationService.instance.disableReminders();
      } else {
        await DonationService.instance.markNotNow();
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      FadePageRoute<void>(page: const SectionsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(),
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
                  onPressed: _handleEnter,
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
              Text(
                'This app is free and supported by donations.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _openSupportScreen,
                child: const Text('Support This App'),
              ),
              const SizedBox(height: 16),
              const Icon(
                Icons.menu_book_rounded,
                size: 72,
                color: Color(0xFF9C6B3E),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          FadePageRoute<void>(page: const HowToUseScreen()),
                        );
                      },
                      icon: const Icon(Icons.help_outline),
                      tooltip: 'Help',
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          FadePageRoute<void>(page: const FontSettingsScreen()),
                        );
                      },
                      icon: const Icon(Icons.settings),
                      tooltip: 'Font settings',
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
