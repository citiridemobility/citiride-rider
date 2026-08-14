import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CompatibleSvgPicture extends StatelessWidget {
  const CompatibleSvgPicture.asset(
    this.assetName, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.semanticsLabel,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  static final Map<String, String> _stringCache = {};
  static final Map<String, Future<String>> _assetCache = {};

  final String assetName;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? semanticsLabel;
  final WidgetBuilder? placeholderBuilder;
  final SvgErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final cachedSvg = _stringCache[assetName];
    final picture = cachedSvg == null
        ? FutureBuilder<String>(
            future: _loadAsset(assetName),
            builder: (context, snapshot) {
              final svg = snapshot.data;
              if (svg == null) {
                return placeholderBuilder?.call(context) ??
                    SizedBox(width: width, height: height);
              }

              return _buildPicture(svg);
            },
          )
        : _buildPicture(cachedSvg);

    if (semanticsLabel == null) {
      return picture;
    }

    return Semantics(label: semanticsLabel, image: true, child: picture);
  }

  Widget _buildPicture(String svg) {
    return SvgPicture.string(
      svg,
      width: width,
      height: height,
      fit: fit,
      excludeFromSemantics: true,
      placeholderBuilder: placeholderBuilder,
      errorBuilder: errorBuilder,
    );
  }

  static Future<void> precacheAssets(Iterable<String> assetNames) async {
    await Future.wait(assetNames.map(_loadAsset));
  }

  static String normalizeSvgForRuntime(String svg) {
    return normalizeFigmaImagePatterns(
      removeUnsupportedDropShadows(removeUnsupportedBlurGlows(svg)),
    );
  }

  static Future<String> _loadAsset(String assetName) {
    final cachedSvg = _stringCache[assetName];
    if (cachedSvg != null) {
      return Future.value(cachedSvg);
    }

    return _assetCache.putIfAbsent(assetName, () async {
      final svg = await rootBundle.loadString(assetName);
      final normalized = normalizeSvgForRuntime(svg);
      _stringCache[assetName] = normalized;
      return normalized;
    });
  }

  @visibleForTesting
  static String removeUnsupportedBlurGlows(String svg) {
    return svg.replaceAll(
      RegExp(r'<g filter="url\(#filter[01]_f_[^\)]+\)">[\s\S]*?</g>\s*'),
      '',
    );
  }

  /// flutter_svg cannot render Figma drop-shadow filters; the offset
  /// SourceGraphic copy often appears as a hard duplicate of the shape.
  @visibleForTesting
  static String removeUnsupportedDropShadows(String svg) {
    var result = svg.replaceAll(
      RegExp(r'''\sfilter="url\(#filter[^"]+_dd_[^"]+\)"'''),
      '',
    );
    result = result.replaceAll(
      RegExp(
        r'<filter\b[^>]*id="filter[^"]+_dd_[^"]+"[\s\S]*?</filter>\s*',
      ),
      '',
    );
    return result;
  }

  @visibleForTesting
  static String normalizeFigmaImagePatterns(String svg) {
    final patternImages = <String, _PatternImage>{};
    final patternMatches = RegExp(
      r'<pattern\b[^>]*id="([^"]+)"[\s\S]*?</pattern>',
    ).allMatches(svg);

    for (final patternMatch in patternMatches) {
      final patternId = patternMatch.group(1);
      final patternMarkup = patternMatch.group(0);
      if (patternId == null || patternMarkup == null) {
        continue;
      }

      final useMatch = RegExp(
        r'<use\b[^>]*(?:xlink:href|href)="#([^"]+)"[^>]*>',
      ).firstMatch(patternMarkup);
      final useMarkup = useMatch?.group(0);
      final imageId = useMatch?.group(1);
      if (useMarkup == null || imageId == null) {
        continue;
      }

      final imageMatch = RegExp(
        '<image\\b(?=[^>]*id="$imageId")[^>]*>',
      ).firstMatch(svg);
      final imageMarkup = imageMatch?.group(0);
      if (imageMarkup == null) {
        continue;
      }

      final imageAttrs = _readAttributes(imageMarkup);
      final href = imageAttrs['xlink:href'] ?? imageAttrs['href'];
      final imageWidth = _parseNumber(imageAttrs['width']);
      final imageHeight = _parseNumber(imageAttrs['height']);
      if (href == null || imageWidth == null || imageHeight == null) {
        continue;
      }

      final useAttrs = _readAttributes(useMarkup);
      patternImages[patternId] = _PatternImage(
        href: href,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        transform: _PatternTransform.parse(useAttrs['transform']),
      );
    }

    if (patternImages.isEmpty) {
      return svg;
    }

    var generatedClipIndex = 0;
    return svg.replaceAllMapped(
      RegExp(r'<rect\b(?=[^>]*fill="url\(#(pattern[^\)]+)\)")[^>]*/>'),
      (match) {
        final rectMarkup = match.group(0)!;
        final patternId = match.group(1)!;
        final patternImage = patternImages[patternId];
        if (patternImage == null) {
          return rectMarkup;
        }

        final attrs = _readAttributes(rectMarkup);
        final x = _parseNumber(attrs['x']) ?? 0;
        final y = _parseNumber(attrs['y']) ?? 0;
        final width = _parseNumber(attrs['width']);
        final height = _parseNumber(attrs['height']);
        if (width == null || height == null) {
          return rectMarkup;
        }

        final clipId = 'figma_image_clip_${generatedClipIndex++}_$patternId'
            .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
        final rectTransform = attrs['transform'];
        final rx = attrs['rx'];
        final ry = attrs['ry'];
        final opacity = attrs['opacity'] ?? attrs['fill-opacity'];
        final patternTransform = patternImage.transform;

        final imageX = x + patternTransform.e * width;
        final imageY = y + patternTransform.f * height;
        final imageWidth = patternImage.imageWidth * patternTransform.a * width;
        final imageHeight =
            patternImage.imageHeight * patternTransform.d * height;

        final clipRectAttrs = StringBuffer()
          ..write('x="${_svgNumber(x)}" ')
          ..write('y="${_svgNumber(y)}" ')
          ..write('width="${_svgNumber(width)}" ')
          ..write('height="${_svgNumber(height)}"');
        if (rx != null) {
          clipRectAttrs.write(' rx="$rx"');
        }
        if (ry != null) {
          clipRectAttrs.write(' ry="$ry"');
        }

        final imageAttrs = StringBuffer()
          ..write('x="${_svgNumber(imageX)}" ')
          ..write('y="${_svgNumber(imageY)}" ')
          ..write('width="${_svgNumber(imageWidth)}" ')
          ..write('height="${_svgNumber(imageHeight)}" ')
          ..write('preserveAspectRatio="none" ')
          ..write('xlink:href="${patternImage.href}" ')
          ..write('href="${patternImage.href}"');

        final clipPath =
            '<clipPath id="$clipId"><rect $clipRectAttrs/></clipPath>';
        final image = '<image $imageAttrs/>';
        final opacityAttr = opacity == null ? '' : ' opacity="$opacity"';
        if (rectTransform == null) {
          return '$clipPath<g$opacityAttr clip-path="url(#$clipId)">$image</g>';
        }

        return '$clipPath<g transform="$rectTransform"$opacityAttr '
            'clip-path="url(#$clipId)">$image</g>';
      },
    );
  }

  static Map<String, String> _readAttributes(String markup) {
    final attrs = <String, String>{};
    for (final match in RegExp(
      r'([A-Za-z_:][-A-Za-z0-9_:.]*)="([^"]*)"',
    ).allMatches(markup)) {
      attrs[match.group(1)!] = match.group(2)!;
    }
    return attrs;
  }

  static double? _parseNumber(String? value) {
    if (value == null) {
      return null;
    }

    return double.tryParse(value.replaceAll(RegExp(r'[^0-9eE+\-.]'), ''));
  }

  static String _svgNumber(double value) {
    final rounded = value.toStringAsFixed(6);
    return rounded
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _PatternImage {
  const _PatternImage({
    required this.href,
    required this.imageWidth,
    required this.imageHeight,
    required this.transform,
  });

  final String href;
  final double imageWidth;
  final double imageHeight;
  final _PatternTransform transform;
}

class _PatternTransform {
  const _PatternTransform({
    required this.a,
    required this.d,
    required this.e,
    required this.f,
  });

  const _PatternTransform.identity() : this(a: 1, d: 1, e: 0, f: 0);

  final double a;
  final double d;
  final double e;
  final double f;

  static _PatternTransform parse(String? transform) {
    if (transform == null || transform.trim().isEmpty) {
      return const _PatternTransform.identity();
    }

    final matrixMatch = RegExp(r'matrix\(([^\)]+)\)').firstMatch(transform);
    if (matrixMatch != null) {
      final values = _numbers(matrixMatch.group(1)!);
      if (values.length >= 6) {
        return _PatternTransform(
          a: values[0],
          d: values[3],
          e: values[4],
          f: values[5],
        );
      }
    }

    var scaleX = 1.0;
    var scaleY = 1.0;
    var translateX = 0.0;
    var translateY = 0.0;

    final scaleMatch = RegExp(r'scale\(([^\)]+)\)').firstMatch(transform);
    if (scaleMatch != null) {
      final values = _numbers(scaleMatch.group(1)!);
      if (values.isNotEmpty) {
        scaleX = values[0];
        scaleY = values.length > 1 ? values[1] : values[0];
      }
    }

    final translateMatch = RegExp(
      r'translate\(([^\)]+)\)',
    ).firstMatch(transform);
    if (translateMatch != null) {
      final values = _numbers(translateMatch.group(1)!);
      if (values.isNotEmpty) {
        translateX = values[0];
        translateY = values.length > 1 ? values[1] : 0;
      }
    }

    return _PatternTransform(
      a: scaleX,
      d: scaleY,
      e: translateX,
      f: translateY,
    );
  }

  static List<double> _numbers(String value) {
    return RegExp(
      r'-?\d*\.?\d+(?:e[-+]?\d+)?',
      caseSensitive: false,
    ).allMatches(value).map((match) => double.parse(match.group(0)!)).toList();
  }
}
