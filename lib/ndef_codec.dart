import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/ndef_record.dart';

/// Well-known prefixes defined by the NFC Forum URI Record Type Definition.
const List<String> uriPrefixes = <String>[
  '',
  'http://www.',
  'https://www.',
  'http://',
  'https://',
  'tel:',
  'mailto:',
  'ftp://anonymous:anonymous@',
  'ftp://ftp.',
  'ftps://',
  'sftp://',
  'smb://',
  'nfs://',
  'ftp://',
  'dav://',
  'news:',
  'telnet://',
  'imap:',
  'rtsp://',
  'urn:',
  'pop:',
  'sip:',
  'sips:',
  'tftp:',
  'btspp://',
  'btl2cap://',
  'btgoep://',
  'tcpobex://',
  'irdaobex://',
  'file://',
  'urn:epc:id:',
  'urn:epc:tag:',
  'urn:epc:pat:',
  'urn:epc:raw:',
  'urn:epc:',
  'urn:nfc:',
];

/// A human readable view of a single NDEF record.
class DecodedRecord {
  const DecodedRecord({
    required this.type,
    required this.value,
    required this.size,
    this.icon = 'text',
  });

  /// Short label of the record type, for example `نص` or `رابط`.
  final String type;

  /// Decoded payload of the record.
  final String value;

  /// Size of the payload in bytes.
  final int size;

  /// Hint used by the UI to pick an icon: `text`, `link`, `data` or `empty`.
  final String icon;
}

/// Builds a Well Known Text record (`T`).
NdefRecord encodeTextRecord(String text, {String language = 'ar'}) {
  final Uint8List languageBytes = Uint8List.fromList(utf8.encode(language));
  final Uint8List textBytes = Uint8List.fromList(utf8.encode(text));
  final Uint8List payload = Uint8List(1 + languageBytes.length + textBytes.length);
  payload[0] = languageBytes.length & 0x3F;
  payload.setRange(1, 1 + languageBytes.length, languageBytes);
  payload.setRange(1 + languageBytes.length, payload.length, textBytes);
  return NdefRecord(
    typeNameFormat: TypeNameFormat.wellKnown,
    type: Uint8List.fromList(const <int>[0x54]),
    identifier: Uint8List(0),
    payload: payload,
  );
}

/// Builds a Well Known URI record (`U`), using the prefix table when possible.
NdefRecord encodeUriRecord(String uri) {
  var prefixIndex = 0;
  final String lower = uri.toLowerCase();
  for (var i = 1; i < uriPrefixes.length; i++) {
    final String prefix = uriPrefixes[i];
    if (lower.startsWith(prefix) && prefix.length > uriPrefixes[prefixIndex].length) {
      prefixIndex = i;
    }
  }
  final String prefix = uriPrefixes[prefixIndex];
  final Uint8List rest = Uint8List.fromList(utf8.encode(uri.substring(prefix.length)));
  final Uint8List payload = Uint8List(1 + rest.length);
  payload[0] = prefixIndex;
  payload.setRange(1, payload.length, rest);
  return NdefRecord(
    typeNameFormat: TypeNameFormat.wellKnown,
    type: Uint8List.fromList(const <int>[0x55]),
    identifier: Uint8List(0),
    payload: payload,
  );
}

/// Adds `https://` to a bare host so the written record stays a valid URI.
String normalizeUri(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final bool hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed);
  return hasScheme ? trimmed : 'https://$trimmed';
}

/// Decodes any record into something that can be displayed.
DecodedRecord decodeRecord(NdefRecord record) {
  switch (record.typeNameFormat) {
    case TypeNameFormat.empty:
      return const DecodedRecord(type: 'فارغ', value: '—', size: 0, icon: 'empty');
    case TypeNameFormat.wellKnown:
      final String type = _ascii(record.type);
      switch (type) {
        case 'T':
          return DecodedRecord(
            type: 'نص (T)',
            value: _decodeTextPayload(record.payload),
            size: record.payload.length,
          );
        case 'U':
          return DecodedRecord(
            type: 'رابط (U)',
            value: _decodeUriPayload(record.payload),
            size: record.payload.length,
            icon: 'link',
          );
        case 'Sp':
          return DecodedRecord(
            type: 'ملصق ذكي (Sp)',
            value: _preview(record.payload),
            size: record.payload.length,
            icon: 'data',
          );
        default:
          return DecodedRecord(
            type: 'قياسي ($type)',
            value: _preview(record.payload),
            size: record.payload.length,
            icon: 'data',
          );
      }
    case TypeNameFormat.media:
      final String mime = _ascii(record.type);
      return DecodedRecord(
        type: 'وسائط ($mime)',
        value: mime.startsWith('text/') ? _decodeUtf8(record.payload) : _preview(record.payload),
        size: record.payload.length,
        icon: 'data',
      );
    case TypeNameFormat.absoluteUri:
      return DecodedRecord(
        type: 'رابط مطلق',
        value: record.type.isEmpty ? _decodeUtf8(record.payload) : _decodeUtf8(record.type),
        size: record.payload.length,
        icon: 'link',
      );
    case TypeNameFormat.external:
      return DecodedRecord(
        type: 'خارجي (${_ascii(record.type)})',
        value: _preview(record.payload),
        size: record.payload.length,
        icon: 'data',
      );
    case TypeNameFormat.unknown:
      return DecodedRecord(
        type: 'غير معروف',
        value: _preview(record.payload),
        size: record.payload.length,
        icon: 'data',
      );
    case TypeNameFormat.unchanged:
      return DecodedRecord(
        type: 'مقطع',
        value: _preview(record.payload),
        size: record.payload.length,
        icon: 'data',
      );
  }
}

String _decodeTextPayload(Uint8List payload) {
  if (payload.isEmpty) {
    return '';
  }
  final int status = payload[0];
  final bool isUtf16 = (status & 0x80) != 0;
  final int languageLength = status & 0x3F;
  final int start = 1 + languageLength;
  if (payload.length <= start) {
    return '';
  }
  final Uint8List body = payload.sublist(start);
  return isUtf16 ? _decodeUtf16(body) : _decodeUtf8(body);
}

String _decodeUriPayload(Uint8List payload) {
  if (payload.isEmpty) {
    return '';
  }
  final int code = payload[0];
  final String prefix = code < uriPrefixes.length ? uriPrefixes[code] : '';
  final String rest = payload.length > 1 ? _decodeUtf8(payload.sublist(1)) : '';
  return '$prefix$rest';
}

String _decodeUtf8(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

String _decodeUtf16(Uint8List bytes) {
  final List<int> codeUnits = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}

String _ascii(Uint8List bytes) => ascii.decode(bytes, allowInvalid: true);

String _preview(Uint8List bytes, {int maxBytes = 32}) {
  if (bytes.isEmpty) {
    return '—';
  }
  final List<int> head = bytes.take(maxBytes).toList();
  final bool printable = head.every((int byte) => byte == 9 || byte == 10 || byte == 13 || (byte >= 32 && byte < 127));
  if (printable) {
    return _decodeUtf8(Uint8List.fromList(head)) + (bytes.length > maxBytes ? '…' : '');
  }
  return head.map((int byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}
