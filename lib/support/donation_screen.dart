import 'package:flutter/material.dart';

import '../utils/font_scale.dart';
import 'donation_service.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  final DonationService _service = DonationService.instance;

  bool _loading = true;
  DonationCatalog? _catalog;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _service.purchaseStatus.value = null;
    try {
      final catalog = await _service.loadCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        _error = catalog.errorMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load support options: $e';
      });
    }
  }

  Future<void> _purchase(DonationCatalogItem item) async {
    final started = await _service.purchase(item);
    if (!mounted) return;
    if (!started) {
      final message = _service.purchaseStatus.value ??
          'This support option is not available yet.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = FontScaleScope.maybeOf(context)?.scale ?? 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Biblical Heritage'),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: _service.donated,
          builder: (context, donated, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _service.purchaseInFlight,
              builder: (context, purchaseInFlight, __) {
                return ValueListenableBuilder<String?>(
                  valueListenable: _service.purchaseStatus,
                  builder: (context, status, ___) {
                    return Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: scheme.outline.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  donated
                                      ? 'Thank you for supporting Biblical Heritage. May God bless the giver.'
                                      : 'Biblical Heritage is intended to remain free. If God has blessed you and you want to support this work, your gift helps make wider translation possible and helps carry the gospel to more lost souls through the app store.',
                                  style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              if (!donated) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Tap one support amount once. The store should respond within a few seconds.',
                                  style: _scaleStyle(theme.textTheme.bodyMedium, scale)?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (status != null && status.trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _PurchaseStatusBanner(
                                  status: status,
                                  inFlight: purchaseInFlight,
                                  donated: donated,
                                  scale: scale,
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  style: _scaleStyle(theme.textTheme.bodySmall, scale)?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              if (_loading)
                                const Center(child: CircularProgressIndicator())
                              else
                                for (final item
                                    in _catalog?.items ?? const <DonationCatalogItem>[])
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _DonationTile(
                                      item: item,
                                      scale: scale,
                                      onPurchase: donated || purchaseInFlight
                                          ? null
                                          : () => _purchase(item),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: purchaseInFlight
                                      ? null
                                      : () async {
                                          final navigator = Navigator.of(context);
                                          await _service.markNotNow();
                                          if (!mounted) return;
                                          navigator.pop();
                                        },
                                  child: const Text('Not now'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: donated || purchaseInFlight
                                      ? null
                                      : () async {
                                          final navigator = Navigator.of(context);
                                          await _service.disableReminders();
                                          if (!mounted) return;
                                          navigator.pop();
                                        },
                                  child: Text(donated ? 'Supported' : 'Don’t remind me'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PurchaseStatusBanner extends StatelessWidget {
  const _PurchaseStatusBanner({
    required this.status,
    required this.inFlight,
    required this.donated,
    required this.scale,
  });

  final String status;
  final bool inFlight;
  final bool donated;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSuccess = donated || status.toLowerCase().contains('thank you');
    final isError = !inFlight && !isSuccess;
    final background = isSuccess
        ? scheme.primary.withValues(alpha: 0.15)
        : isError
            ? scheme.error.withValues(alpha: 0.12)
            : scheme.surface;
    final foreground = isSuccess
        ? scheme.primary
        : isError
            ? scheme.error
            : scheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSuccess
              ? scheme.primary
              : isError
                  ? scheme.error
                  : scheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inFlight)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else
            Icon(
              isSuccess ? Icons.favorite : Icons.info_outline,
              color: foreground,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: _scaleStyle(theme.textTheme.bodyLarge, scale)?.copyWith(
                color: foreground,
                fontWeight: isSuccess ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonationTile extends StatelessWidget {
  const _DonationTile({
    required this.item,
    required this.scale,
    required this.onPurchase,
  });

  final DonationCatalogItem item;
  final double scale;
  final VoidCallback? onPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: _scaleStyle(theme.textTheme.titleMedium, scale)?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: _scaleStyle(theme.textTheme.bodySmall, scale),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onPurchase,
            child: Text(item.priceLabel),
          ),
        ],
      ),
    );
  }
}

TextStyle? _scaleStyle(TextStyle? style, double scale) {
  final fontSize = style?.fontSize;
  if (fontSize == null) return style;
  return style!.copyWith(fontSize: fontSize * scale);
}
