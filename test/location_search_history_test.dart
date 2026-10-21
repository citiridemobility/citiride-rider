import 'package:citiride/core/location/citiride_place.dart';
import 'package:citiride/core/location/location_search_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records unique recent searches with most recent first', () async {
    const store = LocationSearchHistoryStore();

    await store.record(
      const CitiridePlace(
        title: 'Airport Road',
        subtitle: 'Benin City',
        location: LatLng(6.3177, 5.5981),
      ),
    );
    await store.record(
      const CitiridePlace(
        title: 'Ring Road Bus Terminal',
        subtitle: 'Benin City',
        location: LatLng(6.3374, 5.6149),
      ),
    );
    await store.record(
      const CitiridePlace(
        title: 'Airport Road',
        subtitle: 'Benin City',
        location: LatLng(6.3177, 5.5981),
      ),
    );

    final places = await store.load();
    expect(places.map((place) => place.title).toList(), [
      'Airport Road',
      'Ring Road Bus Terminal',
    ]);
  });

  test('does not record current location placeholders', () async {
    const store = LocationSearchHistoryStore();
    await store.record(const CitiridePlace(title: 'Current Location'));
    await store.record(
      const CitiridePlace(title: 'Home', isCurrentLocation: true),
    );

    expect((await store.load()).isEmpty, true);
  });
}
