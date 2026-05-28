import 'package:flutter_test/flutter_test.dart';
import 'package:shiluv_frontend/src/upload_validation.dart';

void main() {
  test('accepts xlsx file names case-insensitively', () {
    expect(isXlsxFileName('programatsia.xlsx'), isTrue);
    expect(isXlsxFileName('PROGRAMATSIA.XLSX'), isTrue);
  });

  test('rejects non-xlsx file names', () {
    expect(isXlsxFileName('programatsia.xls'), isFalse);
    expect(isXlsxFileName('programatsia.xlsx.csv'), isFalse);
    expect(isXlsxFileName('.xlsx'), isFalse);
    expect(isXlsxFileName(''), isFalse);
  });

  test('requests schedule only after programatsia conversion', () {
    expect(shouldFetchSchedule('converted'), isTrue);
    expect(shouldFetchSchedule('missing'), isFalse);
    expect(shouldFetchSchedule('uploaded'), isFalse);
    expect(shouldFetchSchedule('invalid'), isFalse);
  });
}
