import 'package:flutter/material.dart';

import '../data/brhc_database.dart';

class FontScaleController extends ChangeNotifier {
  FontScaleController(this._scale);

  double _scale;

  double get scale => _scale;

  Future<void> setScale(double value) async {
    if (value == _scale) return;
    _scale = value;
    notifyListeners();
    await BrhcDatabase.instance.setFontScale(value);
  }
}

class FontScaleScope extends InheritedNotifier<FontScaleController> {
  const FontScaleScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static FontScaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FontScaleScope>();
    assert(scope != null, 'FontScaleScope not found in widget tree.');
    return scope!.notifier!;
  }

  static FontScaleController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FontScaleScope>()?.notifier;
  }
}
