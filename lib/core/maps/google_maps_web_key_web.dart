import 'package:web/web.dart' as web;

String? readGoogleMapsWebApiKey() {
  final element = web.document.querySelector(
    'meta[name="citiride-google-maps-api-key"]',
  );
  if (element == null) {
    return null;
  }

  final content = element.getAttribute('content')?.trim();
  if (content == null || content.isEmpty || content.contains('YOUR_')) {
    return null;
  }

  return content;
}
