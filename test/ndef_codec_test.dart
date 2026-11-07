import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_read_write/ndef_codec.dart';

void main() {
  group('encodeTextRecord / decodeRecord', () {
    test('round-trips Arabic text through a well known text record', () {
      final NdefRecord record = encodeTextRecord('مرحبًا بالعالم');
      final DecodedRecord decoded = decodeRecord(record);

      expect(record.typeNameFormat, TypeNameFormat.wellKnown);
      expect(record.type, <int>[0x54]);
      expect(decoded.value, 'مرحبًا بالعالم');
      expect(decoded.type, 'Text (T)');
    });

    test('stores the language code in the status byte', () {
      final NdefRecord record = encodeTextRecord('hello', language: 'en');
      expect(record.payload[0], 2);
      expect(decodeRecord(record).value, 'hello');
    });
  });

  group('encodeUriRecord / decodeRecord', () {
    test('uses the well known prefix table', () {
      final NdefRecord record = encodeUriRecord('https://example.com/path');
      expect(record.type, <int>[0x55]);
      expect(record.payload[0], 4);
      expect(decodeRecord(record).value, 'https://example.com/path');
      expect(decodeRecord(record).icon, 'link');
    });

    test('keeps unknown schemes untouched', () {
      final NdefRecord record = encodeUriRecord('tel:+967777000111');
      expect(record.payload[0], 5);
      expect(decodeRecord(record).value, 'tel:+967777000111');
    });
  });

  group('normalizeUri', () {
    test('adds https:// to a bare host', () {
      expect(normalizeUri('example.com'), 'https://example.com');
    });

    test('leaves a complete uri unchanged', () {
      expect(normalizeUri(' mailto:a@b.com '), 'mailto:a@b.com');
    });
  });
}
