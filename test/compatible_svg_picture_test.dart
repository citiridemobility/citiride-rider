import 'package:citiride/shared/widgets/compatible_svg_picture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes slide one car pattern into a cropped image', () async {
    final svg = await rootBundle.loadString(
      'assets/images/onboarding screen1 image.svg',
    );

    final normalized = CompatibleSvgPicture.normalizeFigmaImagePatterns(svg);

    expect(normalized, contains('figma_image_clip_2_pattern2_7050_37985'));
    expect(normalized, contains('href="data:image/png;base64,'));
    expect(normalized, isNot(contains('fill="url(#pattern2_7050_37985)"')));
    expect(normalized, contains('transform="rotate(-134.408 214.016 335.66)"'));
  });

  test(
    'normalizes slide two paper plane pattern into a cropped image',
    () async {
      final svg = await rootBundle.loadString(
        'assets/images/onboarding screen2 image.svg',
      );

      final normalized = CompatibleSvgPicture.normalizeFigmaImagePatterns(svg);

      expect(normalized, contains('figma_image_clip_2_pattern2_'));
      expect(normalized, contains('xlink:href="data:image/png;base64,'));
      expect(normalized, isNot(contains('fill="url(#pattern2_')));
    },
  );
  test('removes unsupported slide two blur glow groups', () async {
    final svg = await rootBundle.loadString(
      'assets/images/onboarding screen2 image.svg',
    );

    final cleaned = CompatibleSvgPicture.removeUnsupportedBlurGlows(svg);

    expect(cleaned, isNot(contains('<g filter="url(#filter0_f_')));
    expect(cleaned, isNot(contains('<g filter="url(#filter1_f_')));
    expect(cleaned, isNot(contains('fill="#0291FF"')));
    expect(cleaned, isNot(contains('fill="#CF08E9"')));
  });

  test('preserves fill-opacity on wallet sign up card logo', () async {
    final svg = await rootBundle.loadString(
      'assets/images/wallet sign up card.svg',
    );

    final normalized = CompatibleSvgPicture.normalizeFigmaImagePatterns(svg);

    expect(normalized, contains('opacity="0.2"'));
    expect(normalized, isNot(contains('fill="url(#pattern2_8893_8522)"')));
  });
}
