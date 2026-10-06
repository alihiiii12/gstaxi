import 'package:flutter_test/flutter_test.dart';
import 'package:syriataxi/core/utils/category_trip_fare_client.dart';

void main() {
  test('category fare includes opening price', () {
    final carType = {
      'openPrice': 5000,
      'KMPrice': 3500,
      'timePrice': 300,
    };
    final fare = categoryTripFareKmMinutesOnly(carType, 2.0, 10.0);
    expect(fare, 5000 + 2 * 3500 + 10 * 300);
  });
}
