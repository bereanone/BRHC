import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/brhc_database.dart';

enum DonationTier {
  support299(
    androidProductId: 'biblical_heritage_support_299',
    appleProductId: 'brhc_support_299',
    fallbackLabel: '\$2.99',
  ),
  support999(
    androidProductId: 'biblical_heritage_support_999',
    appleProductId: 'brhc_support_999',
    fallbackLabel: '\$9.99',
  ),
  support2499(
    androidProductId: 'biblical_heritage_support_2499',
    appleProductId: 'brhc_support_2499',
    fallbackLabel: '\$24.99',
  );

  const DonationTier({
    required this.androidProductId,
    required this.appleProductId,
    required this.fallbackLabel,
  });

  final String androidProductId;
  final String appleProductId;
  final String fallbackLabel;

  String get productId {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return appleProductId;
    }
    return androidProductId;
  }
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
  Timer? _purchaseTimeout;
  DateTime? _lastPurchaseStartedAt;
  bool _sawPendingPurchaseUpdate = false;

  final ValueNotifier<bool> donated = ValueNotifier<bool>(false);
  final ValueNotifier<bool> purchaseInFlight = ValueNotifier<bool>(false);
  final ValueNotifier<String?> purchaseStatus = ValueNotifier<String?>(null);

  String get _storeName {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return 'Apple';
    }
    return 'the store';
  }

  String _friendlyPurchaseError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('authentication failed') ||
        lower.contains('check the account information you entered') ||
        lower.contains('password reuse not available for account')) {
      return '$_storeName could not verify the account for this purchase. Please check the account details and try again.';
    }
    if (lower.contains('usercancelled') || lower.contains('cancelled')) {
      return 'Support purchase cancelled. No donation was made.';
    }
    return 'Support purchase failed. Please try again.';
  }

  void _logPurchaseError(String context, Object error) {
    debugPrint('BRHC purchase error [$context]: $error');
    if (error is PlatformException) {
      debugPrint(
        'BRHC purchase error [$context] code=${error.code} message=${error.message} details=${error.details}',
      );
    }
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    donated.value = await hasDonated();
    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        purchaseInFlight.value = false;
        purchaseStatus.value = _friendlyPurchaseError(error);
      },
    );
  }

  Future<void> dispose() async {
    _purchaseTimeout?.cancel();
    _purchaseTimeout = null;
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
    _purchaseTimeout?.cancel();
    purchaseInFlight.value = true;
    _lastPurchaseStartedAt = DateTime.now();
    _sawPendingPurchaseUpdate = false;
    purchaseStatus.value = 'Opening $_storeName purchase confirmation...';
    final purchaseParam = PurchaseParam(productDetails: item.product!);
    bool started;
    try {
      started = await _iap.buyConsumable(purchaseParam: purchaseParam);
    } on PlatformException catch (error) {
      _logPurchaseError('buyConsumable platform exception', error);
      _purchaseTimeout?.cancel();
      _purchaseTimeout = null;
      purchaseInFlight.value = false;
      purchaseStatus.value = _friendlyPurchaseError(error);
      return false;
    } catch (error) {
      _logPurchaseError('buyConsumable exception', error);
      _purchaseTimeout?.cancel();
      _purchaseTimeout = null;
      purchaseInFlight.value = false;
      purchaseStatus.value = _friendlyPurchaseError(error);
      return false;
    }
    if (!started) {
      purchaseInFlight.value = false;
      purchaseStatus.value =
          'Could not start the support purchase. Please try again.';
      return false;
    }
    purchaseStatus.value =
        'Confirm the purchase in the $_storeName dialog. If nothing appears, try once more.';
    _purchaseTimeout = Timer(const Duration(seconds: 8), () {
      if (!purchaseInFlight.value) return;
      purchaseInFlight.value = false;
      purchaseStatus.value =
          '$_storeName did not show the purchase sheet yet. Please wait a moment, then try one more tap if needed.';
    });
    return true;
  }

  Future<void> _markDonated() async {
    await BrhcDatabase.instance.setSetting(_donatedKey, '1');
    donated.value = true;
    purchaseStatus.value =
        'Thank you for supporting Biblical Heritage. May God bless the giver.';
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      _purchaseTimeout?.cancel();
      _purchaseTimeout = null;
      if (purchase.status == PurchaseStatus.pending) {
        _sawPendingPurchaseUpdate = true;
        purchaseInFlight.value = true;
        purchaseStatus.value =
            'Waiting for $_storeName to finish the support purchase...';
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (purchase.error != null) {
          debugPrint(
            'BRHC purchase stream error code=${purchase.error!.code} message=${purchase.error!.message} details=${purchase.error!.details}',
          );
        }
        purchaseInFlight.value = false;
        purchaseStatus.value = purchase.error?.message != null
            ? _friendlyPurchaseError(purchase.error!.message)
            : 'Support purchase failed. Please try again.';
        _lastPurchaseStartedAt = null;
        _sawPendingPurchaseUpdate = false;
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        purchaseInFlight.value = false;
        _lastPurchaseStartedAt = null;
        _sawPendingPurchaseUpdate = false;
        await _markDonated();
      } else if (purchase.status == PurchaseStatus.canceled) {
        purchaseInFlight.value = false;
        final startedAt = _lastPurchaseStartedAt;
        final secondsSinceStart = startedAt == null
            ? null
            : DateTime.now().difference(startedAt).inSeconds;
        final likelyAuthOrStoreIssue =
            startedAt != null &&
            !_sawPendingPurchaseUpdate &&
            (secondsSinceStart == null || secondsSinceStart >= 2);
        purchaseStatus.value = likelyAuthOrStoreIssue
            ? '$_storeName did not complete the purchase. No donation was made. If you entered account details, please verify them and try again.'
            : 'Support purchase cancelled. No donation was made.';
        _lastPurchaseStartedAt = null;
        _sawPendingPurchaseUpdate = false;
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }
}
