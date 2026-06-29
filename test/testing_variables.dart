import 'package:flutter_config/flutter_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterConfig.loadValueForTesting({});
  });

  test('test variable should be available on test', () {
    FlutterConfig.loadValueForTesting({'BASE_URL': 'https://www.google.com'});
    final baseUrl = FlutterConfig.get('BASE_URL');

    expect(baseUrl, matches('https://www.google.com'));
  });

  test('test variable with integer value', () {
    FlutterConfig.loadValueForTesting({'PORT': 8080});
    expect(FlutterConfig.get('PORT'), 8080);
  });

  test('test variable with boolean value', () {
    FlutterConfig.loadValueForTesting({'DEBUG': true});
    expect(FlutterConfig.get('DEBUG'), true);
  });
}
