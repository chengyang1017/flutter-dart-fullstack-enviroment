import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/enum_parser.dart';
import '../../../../core/utils/input_decoration_value_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../../models/ui_value.dart';
import '../widget_renderer.dart';

class TextFieldUiBuilder {
  const TextFieldUiBuilder();

  Widget call(BuildContext context, UiNode node, WidgetRenderer renderer) {
    const supported = {
      'controller',
      'minLines',
      'maxLines',
      'maxLength',
      'enabled',
      'obscureText',
      'autofocus',
      'readOnly',
      'textAlign',
      'keyboardType',
      'style',
      'decoration',
    };
    renderer.warnUnknown(node, supported);

    var minLines = ValueParser.integer(node.namedArguments['minLines']);
    final maxValue = node.namedArguments['maxLines'];
    int? maxLines;
    if (maxValue is NullUiValue) {
      maxLines = null;
    } else if (maxValue == null) {
      maxLines = 1;
    } else {
      maxLines = ValueParser.integer(maxValue);
    }
    final obscureText =
        ValueParser.boolean(node.namedArguments['obscureText']) ?? false;
    if (minLines != null && maxLines != null && minLines > maxLines) {
      renderer.onWarning(
        context.l10n.tr(
          'TextField 的 minLines ($minLines) 不能大于 maxLines ($maxLines)，预览已自动调整。',
          'TextField minLines ($minLines) cannot be greater than maxLines ($maxLines). The preview adjusted it automatically.',
        ),
      );
      minLines = maxLines;
    }
    if (obscureText &&
        (maxLines == null || maxLines != 1 || (minLines ?? 1) != 1)) {
      renderer.onWarning(
        context.l10n.tr(
          'obscureText 仅支持单行输入，预览已将行数调整为 1。',
          'obscureText only supports single-line input. The preview adjusted the line count to 1.',
        ),
      );
      minLines = 1;
      maxLines = 1;
    }

    final styleValue = node.namedArguments['style'];
    final styleNode =
        styleValue is NodeUiValue && styleValue.value.type == 'TextStyle'
            ? styleValue.value
            : null;
    return _PreviewTextField(
      useSafeController: node.namedArguments.containsKey('controller'),
      minLines: minLines,
      maxLines: maxLines,
      maxLength: ValueParser.integer(node.namedArguments['maxLength']),
      enabled: ValueParser.boolean(node.namedArguments['enabled']),
      obscureText: obscureText,
      autofocus: ValueParser.boolean(node.namedArguments['autofocus']) ?? false,
      readOnly: ValueParser.boolean(node.namedArguments['readOnly']) ?? false,
      textAlign: EnumParser.textAlign(node.namedArguments['textAlign']) ??
          TextAlign.start,
      keyboardType: _keyboardType(node.namedArguments['keyboardType']),
      style: styleNode == null
          ? null
          : TextStyle(
              fontSize:
                  ValueParser.number(styleNode.namedArguments['fontSize']),
              color: ColorParser.parse(styleNode.namedArguments['color']),
              fontWeight:
                  EnumParser.weight(styleNode.namedArguments['fontWeight']),
            ),
      decoration:
          InputDecorationValueParser.parse(node.namedArguments['decoration']),
    );
  }

  TextInputType? _keyboardType(UiValue? value) =>
      switch (EnumParser.id(value)) {
        'TextInputType.text' => TextInputType.text,
        'TextInputType.multiline' => TextInputType.multiline,
        'TextInputType.emailAddress' => TextInputType.emailAddress,
        'TextInputType.number' => TextInputType.number,
        'TextInputType.phone' => TextInputType.phone,
        _ => null,
      };
}

class _PreviewTextField extends StatefulWidget {
  const _PreviewTextField({
    required this.useSafeController,
    required this.minLines,
    required this.maxLines,
    required this.maxLength,
    required this.enabled,
    required this.obscureText,
    required this.autofocus,
    required this.readOnly,
    required this.textAlign,
    required this.keyboardType,
    required this.style,
    required this.decoration,
  });

  final bool useSafeController;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final bool? enabled;
  final bool obscureText;
  final bool autofocus;
  final bool readOnly;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final InputDecoration decoration;

  @override
  State<_PreviewTextField> createState() => _PreviewTextFieldState();
}

class _PreviewTextFieldState extends State<_PreviewTextField> {
  TextEditingController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.useSafeController) _controller = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant _PreviewTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.useSafeController && _controller == null) {
      _controller = TextEditingController();
    } else if (!widget.useSafeController && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        enabled: widget.enabled,
        obscureText: widget.obscureText,
        autofocus: widget.autofocus,
        readOnly: widget.readOnly,
        textAlign: widget.textAlign,
        keyboardType: widget.keyboardType,
        style: widget.style,
        decoration: widget.decoration,
      );
}
