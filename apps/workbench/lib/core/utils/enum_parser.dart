import 'package:flutter/material.dart';
import '../../features/playground/models/ui_value.dart';

abstract final class EnumParser {
  static String? id(UiValue? v) => v is IdentifierUiValue ? v.value : null;
  static MainAxisAlignment main(UiValue? v) =>
      const {
        'MainAxisAlignment.start': MainAxisAlignment.start,
        'MainAxisAlignment.center': MainAxisAlignment.center,
        'MainAxisAlignment.end': MainAxisAlignment.end,
        'MainAxisAlignment.spaceBetween': MainAxisAlignment.spaceBetween,
        'MainAxisAlignment.spaceAround': MainAxisAlignment.spaceAround,
        'MainAxisAlignment.spaceEvenly': MainAxisAlignment.spaceEvenly,
      }[id(v)] ??
      MainAxisAlignment.start;
  static CrossAxisAlignment cross(UiValue? v) =>
      const {
        'CrossAxisAlignment.start': CrossAxisAlignment.start,
        'CrossAxisAlignment.center': CrossAxisAlignment.center,
        'CrossAxisAlignment.end': CrossAxisAlignment.end,
        'CrossAxisAlignment.stretch': CrossAxisAlignment.stretch,
      }[id(v)] ??
      CrossAxisAlignment.center;
  static MainAxisSize size(UiValue? v) =>
      id(v) == 'MainAxisSize.min' ? MainAxisSize.min : MainAxisSize.max;
  static Alignment alignment(UiValue? v) =>
      const {
        'Alignment.center': Alignment.center,
        'Alignment.centerLeft': Alignment.centerLeft,
        'Alignment.centerRight': Alignment.centerRight,
        'Alignment.topCenter': Alignment.topCenter,
        'Alignment.bottomCenter': Alignment.bottomCenter,
      }[id(v)] ??
      Alignment.center;
  static FontWeight weight(UiValue? v) =>
      const {
        'FontWeight.normal': FontWeight.normal,
        'FontWeight.bold': FontWeight.bold,
        'FontWeight.w500': FontWeight.w500,
        'FontWeight.w600': FontWeight.w600,
        'FontWeight.w700': FontWeight.w700,
      }[id(v)] ??
      FontWeight.normal;
  static TextAlign? textAlign(UiValue? v) => const {
        'TextAlign.left': TextAlign.left,
        'TextAlign.center': TextAlign.center,
        'TextAlign.right': TextAlign.right,
        'TextAlign.start': TextAlign.start,
        'TextAlign.end': TextAlign.end,
      }[id(v)];
}
