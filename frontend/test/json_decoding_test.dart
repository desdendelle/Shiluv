import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiluv_frontend/src/json_decoding.dart';

void main() {
  test('decodes Hebrew JSON responses as UTF-8', () {
    final bytes = utf8.encode(
      '{"display_name":"מנהל","label":"משמרת בוקר","location":"מוקד"}',
    );

    final decoded = decodeJsonObjectFromBytes(bytes);

    expect(decoded['display_name'], 'מנהל');
    expect(decoded['label'], 'משמרת בוקר');
    expect(decoded['location'], 'מוקד');
  });
}
