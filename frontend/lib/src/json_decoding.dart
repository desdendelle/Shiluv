import 'dart:convert';

Map<String, dynamic> decodeJsonObjectFromBytes(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  throw const FormatException('Expected a JSON object response');
}
