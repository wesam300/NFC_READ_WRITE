import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import 'ndef_codec.dart';

void main() {
  runApp(const NfcApp());
}

class NfcApp extends StatelessWidget {
  const NfcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC Reader & Writer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DB9A8),
          brightness: Brightness.dark,
        ),
      ),
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomePage(),
    );
  }
}

enum NfcMode { read, write }

enum RecordKind { text, uri }

class TagSummary {
  const TagSummary({
    required this.writable,
    required this.capacity,
    this.messageSize,
  });

  final bool writable;
  final int capacity;
  final int? messageSize;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _valueController = TextEditingController();

  NfcAvailability? _availability;
  String? _availabilityError;
  bool _checkingAvailability = true;

  NfcMode _mode = NfcMode.read;
  RecordKind _kind = RecordKind.text;

  bool _busy = false;
  String? _errorMessage;
  String? _successMessage;
  TagSummary? _tag;
  List<DecodedRecord> _records = const <DecodedRecord>[];

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  bool get _isIos => Theme.of(context).platform == TargetPlatform.iOS;

  Future<void> _refreshAvailability() async {
    try {
      final NfcAvailability availability = await NfcManager.instance.checkAvailability();
      if (!mounted) {
        return;
      }
      setState(() {
        _availability = availability;
        _availabilityError = null;
        _checkingAvailability = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availability = null;
        _availabilityError = '$error';
        _checkingAvailability = false;
      });
    }
  }

  Future<void> _start() async {
    if (_busy) {
      return;
    }
    if (_mode == NfcMode.write && _valueController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Type some text or a link before writing.';
        _successMessage = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
      _successMessage = null;
      _tag = null;
      _records = const <DecodedRecord>[];
    });

    var handled = false;
    try {
      // The availability check is only advisory: on iOS it also fails when the
      // app was signed without the NFC entitlement, so try the session anyway
      // and report the exact error from CoreNFC.
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        alertMessageIos: _mode == NfcMode.read
            ? 'Hold the top of your iPhone near the NFC tag to read it'
            : 'Hold the top of your iPhone near the NFC tag to write it',
        invalidateAfterFirstReadIos: false,
        onSessionErrorIos: _onIosSessionError,
        onDiscovered: (NfcTag tag) async {
          if (handled) {
            return;
          }
          handled = true;
          await _handleTag(tag);
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorMessage = _describeStartFailure(error);
      });
    }
  }

  String _describeStartFailure(Object error) {
    final String raw = error.toString();
    if (_isIos) {
      return 'Could not start the NFC session. $raw\n\n'
          'iOS only allows NFC when the app is signed with the NFC entitlement '
          '(paid Apple Developer account). Free signing and the Simulator cannot '
          'start an NFC session, even though the iPhone supports NFC.';
    }
    return 'Could not start the NFC session: $raw';
  }

  void _onIosSessionError(NfcReaderSessionErrorIos error) {
    if (!mounted) {
      return;
    }
    final bool userCanceled =
        error.code == NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled ||
        error.code == NfcReaderErrorCodeIos.readerSessionInvalidationErrorFirstNDEFTagRead;
    if (userCanceled) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = false;
      _errorMessage = switch (error.code) {
        NfcReaderErrorCodeIos.readerErrorUnsupportedFeature =>
          'CoreNFC refused the session: this build is not allowed to use NFC. '
              'The app must be signed with the NFC entitlement (paid Apple Developer account).',
        NfcReaderErrorCodeIos.readerSessionInvalidationErrorSessionTimeout =>
          'The NFC session timed out. Hold the top of the iPhone against the tag and try again.',
        NfcReaderErrorCodeIos.readerSessionInvalidationErrorSystemIsBusy =>
          'NFC is busy in another app. Close it and try again.',
        _ => error.message,
      };
    });
  }

  Future<void> _handleTag(NfcTag tag) async {
    final Ndef? ndef = Ndef.from(tag);
    if (ndef == null) {
      await _stop(error: 'This tag does not support NDEF. Try an NDEF tag such as NTAG213/215/216.');
      return;
    }

    if (_mode == NfcMode.read) {
      await _read(ndef);
    } else {
      await _write(ndef);
    }
  }

  Future<void> _read(Ndef ndef) async {
    try {
      final NdefMessage? message = await ndef.read() ?? ndef.cachedMessage;
      final List<DecodedRecord> records = message == null
          ? const <DecodedRecord>[]
          : message.records.map(decodeRecord).toList(growable: false);
      await _stop(
        success: records.isEmpty ? 'Read complete: this tag is empty.' : 'Read ${records.length} record(s) from the tag.',
        tag: TagSummary(
          writable: ndef.isWritable,
          capacity: ndef.maxSize,
          messageSize: message?.byteLength,
        ),
        records: records,
        alert: 'Tag read successfully',
      );
    } catch (error) {
      await _stop(error: 'Could not read the tag: $error');
    }
  }

  Future<void> _write(Ndef ndef) async {
    if (!ndef.isWritable) {
      await _stop(error: 'This tag is read-only (locked or full), so it cannot be written.');
      return;
    }
    final String raw = _valueController.text.trim();
    final NdefRecord record = _kind == RecordKind.text
        ? encodeTextRecord(raw)
        : encodeUriRecord(normalizeUri(raw));
    final NdefMessage message = NdefMessage(records: <NdefRecord>[record]);
    if (ndef.maxSize > 0 && message.byteLength > ndef.maxSize) {
      await _stop(
        error: 'The data is ${message.byteLength} bytes but the tag only holds ${ndef.maxSize} bytes.',
      );
      return;
    }
    try {
      await ndef.write(message: message);
      await _stop(
        success: 'The tag was written successfully.',
        tag: TagSummary(
          writable: ndef.isWritable,
          capacity: ndef.maxSize,
          messageSize: message.byteLength,
        ),
        records: <DecodedRecord>[decodeRecord(record)],
        alert: 'Tag written successfully',
      );
    } catch (error) {
      await _stop(error: 'Could not write the tag: $error');
    }
  }

  Future<void> _stop({
    String? success,
    String? error,
    TagSummary? tag,
    List<DecodedRecord>? records,
    String? alert,
  }) async {
    try {
      await NfcManager.instance.stopSession(
        alertMessageIos: error == null ? (alert ?? success) : null,
        errorMessageIos: error,
      );
    } catch (stopError) {
      debugPrint('stopSession failed: $stopError');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (success != null) {
        _successMessage = success;
      }
      if (error != null) {
        _errorMessage = error;
      }
      if (tag != null) {
        _tag = tag;
      }
      if (records != null) {
        _records = records;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Reader & Writer'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: 'Check NFC again',
            onPressed: () {
              setState(() => _checkingAvailability = true);
              _refreshAvailability();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            _availabilityCard(theme),
            const SizedBox(height: 16),
            SegmentedButton<NfcMode>(
              segments: const <ButtonSegment<NfcMode>>[
                ButtonSegment<NfcMode>(
                  value: NfcMode.read,
                  label: Text('Read'),
                  icon: Icon(Icons.download_rounded),
                ),
                ButtonSegment<NfcMode>(
                  value: NfcMode.write,
                  label: Text('Write'),
                  icon: Icon(Icons.upload_rounded),
                ),
              ],
              selected: <NfcMode>{_mode},
              onSelectionChanged: _busy
                  ? null
                  : (Set<NfcMode> selection) {
                      setState(() => _mode = selection.first);
                    },
            ),
            const SizedBox(height: 16),
            if (_mode == NfcMode.write) ...<Widget>[
              SegmentedButton<RecordKind>(
                segments: const <ButtonSegment<RecordKind>>[
                  ButtonSegment<RecordKind>(value: RecordKind.text, label: Text('Text')),
                  ButtonSegment<RecordKind>(value: RecordKind.uri, label: Text('Link')),
                ],
                selected: <RecordKind>{_kind},
                onSelectionChanged: _busy
                    ? null
                    : (Set<RecordKind> selection) {
                        setState(() => _kind = selection.first);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valueController,
                enabled: !_busy,
                minLines: 1,
                maxLines: 4,
                textDirection: _kind == RecordKind.uri ? TextDirection.ltr : null,
                keyboardType: _kind == RecordKind.uri ? TextInputType.url : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _kind == RecordKind.uri ? 'Link' : 'Text',
                  hintText: _kind == RecordKind.uri ? 'https://example.com' : 'Data you want to store on the tag',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    _kind == RecordKind.uri ? Icons.link_rounded : Icons.notes_rounded,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.nfc_rounded),
              label: Text(
                _busy
                    ? 'Waiting for a tag…'
                    : (_mode == NfcMode.read ? 'Start reading' : 'Start writing'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hold the top of the iPhone near the tag without touching it. Remove thick cases first.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_errorMessage != null || _successMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              _resultBanner(theme),
            ],
            if (_tag != null) ...<Widget>[
              const SizedBox(height: 16),
              _tagCard(theme),
            ],
            if (_records.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Tag contents', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._records.map((DecodedRecord record) => _recordTile(theme, record)),
            ],
            const SizedBox(height: 24),
            Text(
              'Note: on iOS the NFC reader only works when the app is signed with the NFC '
              'entitlement, which requires a paid Apple Developer account. Free signing installs '
              'the app but cannot use NFC.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _availabilityCard(ThemeData theme) {
    final ColorScheme colors = theme.colorScheme;
    IconData icon = Icons.nfc_rounded;
    Color color = colors.primary;
    String title;
    String subtitle;

    if (_checkingAvailability) {
      color = colors.onSurfaceVariant;
      title = 'Checking NFC support…';
      subtitle = 'Looking for an NFC reader on this device.';
    } else if (_availabilityError != null) {
      color = colors.error;
      icon = Icons.error_outline_rounded;
      title = 'NFC status unknown';
      subtitle = '${_availabilityError!}\nYou can still tap the button to try a session.';
    } else if (_availability == NfcAvailability.enabled) {
      color = const Color(0xFF2ECC71);
      title = 'NFC is ready';
      subtitle = 'Read and write NDEF tags.';
    } else if (_availability == NfcAvailability.disabled) {
      color = Colors.orangeAccent;
      icon = Icons.sensors_off_rounded;
      title = 'NFC is turned off';
      subtitle = 'Enable NFC in the device settings, then tap refresh.';
    } else {
      color = Colors.orangeAccent;
      icon = Icons.sensors_off_rounded;
      title = 'NFC session not available';
      subtitle = _isIos
          ? 'This iPhone may support NFC, but iOS only allows it for apps signed with the NFC '
              'entitlement (paid Apple Developer account). Tap the button to try — the exact '
              'CoreNFC error will be shown.'
          : 'This device does not expose an NFC reader to the app.';
    }

    return Card(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultBanner(ThemeData theme) {
    final ColorScheme colors = theme.colorScheme;
    final bool isError = _errorMessage != null;
    final Color color = isError ? colors.error : const Color(0xFF2ECC71);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(_errorMessage ?? _successMessage ?? '', style: TextStyle(color: color))),
        ],
      ),
    );
  }

  Widget _tagCard(ThemeData theme) {
    final TagSummary tag = _tag!;
    final List<Widget> rows = <Widget>[
      _infoRow('Writable', tag.writable ? 'Yes' : 'No (read-only)'),
      _infoRow('Tag capacity', tag.capacity > 0 ? '${tag.capacity} bytes' : 'Unknown'),
      if (tag.messageSize != null) _infoRow('Message size', '${tag.messageSize} bytes'),
    ];
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Tag details', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _recordTile(ThemeData theme, DecodedRecord record) {
    final IconData icon = switch (record.icon) {
      'link' => Icons.link_rounded,
      'data' => Icons.data_object_rounded,
      'empty' => Icons.remove_circle_outline_rounded,
      _ => Icons.notes_rounded,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainer,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(record.type),
        subtitle: SelectableText(
          record.value.isEmpty ? '—' : record.value,
          style: theme.textTheme.bodyMedium,
        ),
        trailing: Text('${record.size} B', style: theme.textTheme.bodySmall),
      ),
    );
  }
}
