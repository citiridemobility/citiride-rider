import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'citiride_place.dart';

class LocationSearchHistoryStore {
  const LocationSearchHistoryStore();

  static const key = 'citiride.location_search_history';
  static const maxItems = 8;

  Future<List<CitiridePlace>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) {
        return const [];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => CitiridePlace.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((place) => place.title.trim().isNotEmpty)
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<void> record(CitiridePlace place) async {
    if (!_shouldRecord(place)) {
      return;
    }

    try {
      final current = [...await load()];
      current.removeWhere((item) => _isSamePlace(item, place));
      current.insert(0, place);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(
          current.take(maxItems).map((item) => item.toJson()).toList(),
        ),
      );
    } on Object {
      // Search history must never block selecting a place.
    }
  }

  bool _shouldRecord(CitiridePlace place) {
    if (place.isCurrentLocation) {
      return false;
    }

    final title = place.title.trim().toLowerCase();
    if (title.isEmpty) {
      return false;
    }

    return title != 'current location' &&
        title != 'my location' &&
        title != 'set location' &&
        title != 'locating...';
  }

  bool _isSamePlace(CitiridePlace first, CitiridePlace second) {
    final firstId = first.placeId?.trim();
    final secondId = second.placeId?.trim();
    if (firstId != null &&
        firstId.isNotEmpty &&
        secondId != null &&
        secondId.isNotEmpty) {
      return firstId == secondId;
    }

    return first.title.trim().toLowerCase() ==
        second.title.trim().toLowerCase();
  }
}
