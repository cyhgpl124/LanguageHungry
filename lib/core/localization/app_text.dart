import 'package:flutter/material.dart';

import 'app_text_catalog.dart';

class AppText extends StatelessWidget {
  static final _templates = AppTextCatalog.templates.entries
      .map(_AppTextTemplate.new)
      .toList(growable: false);
  static final _placeholderPattern = RegExp(r'\{(\d+)\}');

  const AppText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  static String localize(BuildContext context, String value) {
    final locale = Localizations.localeOf(context).languageCode;
    final translation = AppTextCatalog.translations[value]?[locale];
    if (translation != null) return translation;

    for (final template in _templates) {
      final match = template.pattern.firstMatch(value);
      if (match == null) continue;

      final values = <int, String>{};
      for (var index = 0; index < template.placeholders.length; index++) {
        values[template.placeholders[index]] = match.group(index + 1)!;
      }
      final localizedTemplate = template.translations[locale] ??
          template.translations['ko'] ??
          template.source;
      return localizedTemplate.replaceAllMapped(
        _placeholderPattern,
        (placeholder) =>
            values[int.parse(placeholder.group(1)!)] ?? placeholder[0]!,
      );
    }

    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      localize(context, data),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

class _AppTextTemplate {
  _AppTextTemplate(MapEntry<String, Map<String, String>> entry)
      : source = entry.key,
        translations = entry.value,
        placeholders = _placeholderPattern
            .allMatches(entry.key)
            .map((match) => int.parse(match.group(1)!))
            .toList(growable: false),
        pattern = _buildPattern(entry.key);

  static final _placeholderPattern = RegExp(r'\{(\d+)\}');

  final String source;
  final Map<String, String> translations;
  final List<int> placeholders;
  final RegExp pattern;

  static RegExp _buildPattern(String source) {
    final matches = _placeholderPattern.allMatches(source);
    final pattern = StringBuffer('^');
    var sourceOffset = 0;
    for (final placeholder in matches) {
      pattern.write(
        RegExp.escape(source.substring(sourceOffset, placeholder.start)),
      );
      pattern.write('(.*?)');
      sourceOffset = placeholder.end;
    }
    pattern
      ..write(RegExp.escape(source.substring(sourceOffset)))
      ..write(r'$');
    return RegExp(pattern.toString());
  }
}
