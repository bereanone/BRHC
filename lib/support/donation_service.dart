import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/brhc_database.dart';

enum DonationTier {
  support299('biblical_heritage_support_299', '\$2.99'),
  support999('biblical_heritage_support_999', '\$9.99'),
  support2499('biblical_heritage_support_2499', '\$24.99');

  const DonationTier(this.productId, this.fallbackLabel);

  final String productId;
  final String fallbackLabel;
}

class DonationCatalogItem {
  final DonationTier tier;
  final ProductDetails? product;

  const DonationCatalogItem({
    required this.tier,
    required this.product,
  });

  String get title {
    switch (tier) {
      case DonationTier.support299:
        return 'Support';
      case DonationTier.support999:
        return 'Bless More';
      case DonationTier.support2499:
        return 'Bless Abundantly';
    }
  }

  String get priceLabel => product?.price ?? tier.fallbackLabel;

  String get description {
    switch (tier) {
      case DonationTier.support299:
        return 'A gentle thank-you gift through the app store.';
      case DonationTier.support999:
        return 'Support the ministry as God has blessed you.';
      case DonationTier.support2499:
        return 'A larger one-time encouragement through the app store.';
    }
  }
}

class DonationCatalog {
  final bool storeAvailable;
  final List<DonationCatalogItem> items;
  final String? errorMessage;

  const DonationCatalog({
    required this.storeAvailable,
    required this.items,
    this.errorMessage,
  });
}

class DonationService {
  DonationService._();

  static final DonationService instance = DonationService._();

  static const String _donatedKey = 'support.donated';
  static const String _remindersDisabledKey = 'support.reminders_disabled';
  static const String _lastPromptAtKey = 'support.last_prompt_at';
  static const String _launchCountKey = 'support.launch_count';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _started = false;

  final ValueNotifier<bool> donated = ValueNotifier<bool>(false);
  final ValueNotifier<bool> purchaseInFlight = ValueNotifier<bool>(false);
  final ValueNotifier<String?> purchaseStatus = ValueNotifier<String?>(null);

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    donated.value = await hasDonated();
    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        purchaseInFlight.value = false;
        purchaseStatus.value = 'Support purchase failed: $error';
      },
    );
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _started = false;
  }

  Future<bool> hasDonated() async {
    final raw = await BrhcDatabase.instance.getSetting(_donatedKey);
    return raw == '1';
  }

  Future<bool> remindersDisabled() async {
    final raw = await BrhcDatabase.instance.getSetting(_remindersDisabledKey);
    return raw == '1';
  }

  Future<void> markNotNow() async {
    await BrhcDatabase.instance.setSetting(
      _lastPromptAtKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> disableReminders() async {
    await BrhcDatabase.instance.setSetting(_remindersDisabledKey, '1');
  }

  Future<void> recordLaunch() async {
    final raw = await BrhcDatabase.instance.getSetting(_launchCountKey);
    final current = int.tryParse(raw ?? '') ?? 0;
    await BrhcDatabase.instance.setSetting(_launchCountKey, '${current + 1}');
  }

  Future<bool> shouldPrompt() async {
    if (await hasDonated()) return false;
    if (await remindersDisabled()) return false;
    final lastPromptAt = int.tryParse(
          await BrhcDatabase.instance.getSetting(_lastPromptAtKey) ?? '',
        ) ??
        0;
    if (lastPromptAt <= 0) return true;
    final since = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(lastPromptAt));
    return since.inDays >= 14;
  }

  Future<DonationCatalog> loadCatalog() async {
    await ensureStarted();
    final available = await _iap.isAvailable();
    if (!available) {
      return DonationCatalog(
        storeAvailable: false,
        items: DonationTier.values
            .map((tier) => DonationCatalogItem(tier: tier, product: null))
            .toList(growable: false),
        errorMessage: 'The app store is not available right now on this device.',
      );
    }
    final response = await _iap.queryProductDetails(
      DonationTier.values.map((tier) => tier.productId).toSet(),
    );
    final byId = <String, ProductDetails>{
      for (final product in response.productDetails) product.id: product,
    };
    return DonationCatalog(
      storeAvailable: true,
      items: DonationTier.values
          .map(
            (tier) => DonationCatalogItem(
              tier: tier,
              product: byId[tier.productId],
            ),
          )
          .toList(growable: false),
      errorMessage: response.error?.message,
    );
  }

  Future<bool> purchase(DonationCatalogItem item) async {
    await ensureStarted();
    if (item.product == null) {
      purchaseStatus.value =
          'This support option is not configured in the store yet.';
      return false;
    }
    purchaseInFlight.value = true;
    purchaseStatus.value = 'Starting support purchase...';
    final purchaseParam = PurchaseParam(productDetails: item.product!);
    return _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _markDonated() async {
    await BrhcDatabase.instance.setSetting(_donatedKey, '1');
    donated.value = true;
    purchaseStatus.value =
        'Thank you for supporting Biblical Heritage through the app store.';
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      if (purchase.status == PurchaseStatus.pending) {
        purchaseInFlight.value = true;
        purchaseStatus.value = 'Waiting for the app store...';
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        purchaseInFlight.value = false;
        purchaseStatus.value =
            purchase.error?.message ?? 'Support purchase failed.';
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        purchaseInFlight.value = false;
        await _markDonated();
      } else if (purchase.status == PurchaseStatus.canceled) {
        purchaseInFlight.value = false;
        purchaseStatus.value = 'Support purchase cancelled.';
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }
}
