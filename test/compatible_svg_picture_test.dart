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

    expect(normalized.contains('figma_image_clip_2_pattern2_7050_37985'), true);
    expect(normalized.contains('href="data:image/png;base64,'), true);
    expect(normalized.contains('fill="url(#pattern2_7050_37985)"'), false);
    expect(
      normalized.contains('transform="rotate(-134.408 214.016 335.66)"'),
      true,
    );
  });

  test(
    'normalizes slide two paper plane pattern into a cropped image',
    () async {
      final svg = await rootBundle.loadString(
        'assets/images/onboarding screen2 image.svg',
      );

      final normalized = CompatibleSvgPicture.normalizeFigmaImagePatterns(svg);

      expect(normalized.contains('figma_image_clip_2_pattern2_'), true);
      expect(normalized.contains('xlink:href="data:image/png;base64,'), true);
      expect(normalized.contains('fill="url(#pattern2_'), false);
    },
  );
  test('removes unsupported slide two blur glow groups', () async {
    final svg = await rootBundle.loadString(
      'assets/images/onboarding screen2 image.svg',
    );

    final cleaned = CompatibleSvgPicture.removeUnsupportedBlurGlows(svg);

    expect(cleaned.contains('<g filter="url(#filter0_f_'), false);
    expect(cleaned.contains('<g filter="url(#filter1_f_'), false);
    expect(cleaned.contains('fill="#0291FF"'), false);
    expect(cleaned.contains('fill="#CF08E9"'), false);
  });

  test('preserves fill-opacity on wallet sign up card logo', () async {
    final svg = await rootBundle.loadString(
      'assets/images/wallet sign up card.svg',
    );

    final normalized = CompatibleSvgPicture.normalizeFigmaImagePatterns(svg);

    expect(normalized.contains('opacity="0.2"'), true);
    expect(normalized.contains('fill="url(#pattern2_8893_8522)"'), false);
  });
}
