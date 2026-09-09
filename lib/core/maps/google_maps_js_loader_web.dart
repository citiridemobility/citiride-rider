import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _scriptId = 'citiride-google-maps-js';
Completer<bool>? _loadCompleter;

Future<bool> ensureGoogleMapsJsSdk({required String apiKey}) async {
  final trimmedKey = apiKey.trim();
  if (trimmedKey.isEmpty) {
    return false;
  }

  if (_isMapsSdkReady()) {
    return true;
  }

  final completer = _loadCompleter ??= Completer<bool>();

  // index.html (or a prior call) may already have injected Maps JS. Never load
  // the API twice — that breaks MapTypeId / white tiles on Flutter web.
  if (web.document.getElementById(_scriptId) != null ||
      _hasMapsScriptTag()) {
    return _waitForSdk(completer);
  }

  // Classic callback loading — `loading=async` can resolve before MapTypeId exists
  // and causes Flutter web's ROADMAP TypeError / white broken maps.
  final callbackName = 'citirideGoogleMapsReady';
  globalContext.setProperty(
    callbackName.toJS,
    (() {
      if (!completer.isCompleted) {
        completer.complete(_isMapsSdkReady());
      }
    }).toJS,
  );

  final script = web.HTMLScriptElement()
    ..id = _scriptId
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeComponent(trimmedKey)}&libraries=places&callback=$callbackName'
    ..async = true;

  script.onerror = (() {
    if (!completer.isCompleted) {
      completer.complete(false);
    }
  }).toJS;

  web.document.head?.appendChild(script);
  return _waitForSdk(completer);
}

bool _hasMapsScriptTag() {
  final scripts = web.document.getElementsByTagName('script');
  final length = scripts.length;
  for (var i = 0; i < length; i += 1) {
    final node = scripts.item(i);
    if (node == null) continue;
    final src = (node as web.HTMLScriptElement).src;
    if (src.contains('maps.googleapis.com/maps/api/js')) {
      return true;
    }
  }
  return false;
}

Future<bool> _waitForSdk(Completer<bool> completer) async {
  if (_isMapsSdkReady()) {
    if (!completer.isCompleted) {
      completer.complete(true);
    }
    return true;
  }

  // Poll briefly in case the script tag already existed from index.html.
  for (var i = 0; i < 40; i += 1) {
    if (_isMapsSdkReady()) {
      if (!completer.isCompleted) {
        completer.complete(true);
      }
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  return completer.future.timeout(
    const Duration(seconds: 8),
    onTimeout: _isMapsSdkReady,
  );
}

bool _isMapsSdkReady() {
  final google = globalContext.getProperty<JSAny?>('google'.toJS);
  if (google == null || google.isUndefinedOrNull) {
    return false;
  }

  final googleObject = google as JSObject;
  final maps = googleObject.getProperty<JSAny?>('maps'.toJS);
  if (maps == null || maps.isUndefinedOrNull) {
    return false;
  }

  final mapsObject = maps as JSObject;
  final mapTypeId = mapsObject.getProperty<JSAny?>('MapTypeId'.toJS);
  return mapTypeId != null && !mapTypeId.isUndefinedOrNull;
}
