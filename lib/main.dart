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
      title: 'NFC قراءة وكتابة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1DB9A8),
          brightness: Brightness.dark,
        ),
      ),
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
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
        _errorMessage = 'اكتب نصًا أو رابطًا قبل بدء الكتابة.';
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
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        alertMessageIos: _mode == NfcMode.read
            ? 'قرّب الجزء العلوي من الآيفون من وسم NFC للقراءة'
            : 'قرّب الجزء العلوي من الآيفون من الوسم للكتابة',
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
        _errorMessage = 'تعذّر بدء جلسة NFC: $error';
      });
    }
  }

  void _onIosSessionError(NfcReaderSessionErrorIos error) {
    if (!mounted) {
      return;
    }
    final bool userCanceled =
        error.code == NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled ||
        error.code == NfcReaderErrorCodeIos.readerSessionInvalidationErrorFirstNDEFTagRead;
    setState(() {
      _busy = false;
      if (!userCanceled) {
        _errorMessage = error.message;
      }
    });
  }

  Future<void> _handleTag(NfcTag tag) async {
    final Ndef? ndef = Ndef.from(tag);
    if (ndef == null) {
      await _stop(error: 'هذا الوسم لا يدعم NDEF. جرّب وسمًا آخر (NTAG213/215/216 مثلًا).');
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
        success: records.isEmpty ? 'تمت القراءة: الوسم فارغ.' : 'تمت قراءة ${records.length} سجل من الوسم.',
        tag: TagSummary(
          writable: ndef.isWritable,
          capacity: ndef.maxSize,
          messageSize: message?.byteLength,
        ),
        records: records,
        alert: 'تمت القراءة بنجاح',
      );
    } catch (error) {
      await _stop(error: 'تعذّرت قراءة الوسم: $error');
    }
  }

  Future<void> _write(Ndef ndef) async {
    if (!ndef.isWritable) {
      await _stop(error: 'هذا الوسم غير قابل للكتابة (مقفل أو ممتلئ).');
      return;
    }
    final String raw = _valueController.text.trim();
    final NdefRecord record = _kind == RecordKind.text
        ? encodeTextRecord(raw)
        : encodeUriRecord(normalizeUri(raw));
    final NdefMessage message = NdefMessage(records: <NdefRecord>[record]);
    if (ndef.maxSize > 0 && message.byteLength > ndef.maxSize) {
      await _stop(
        error: 'حجم البيانات (${message.byteLength} بايت) أكبر من سعة الوسم (${ndef.maxSize} بايت).',
      );
      return;
    }
    try {
      await ndef.write(message: message);
      await _stop(
        success: 'تمت الكتابة على الوسم بنجاح.',
        tag: TagSummary(
          writable: ndef.isWritable,
          capacity: ndef.maxSize,
          messageSize: message.byteLength,
        ),
        records: <DecodedRecord>[decodeRecord(record)],
        alert: 'تمت الكتابة بنجاح',
      );
    } catch (error) {
      await _stop(error: 'تعذّرت الكتابة على الوسم: $error');
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
        title: const Text('NFC قراءة وكتابة'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: 'إعادة فحص NFC',
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
                  label: Text('قراءة'),
                  icon: Icon(Icons.download_rounded),
                ),
                ButtonSegment<NfcMode>(
                  value: NfcMode.write,
                  label: Text('كتابة'),
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
                  ButtonSegment<RecordKind>(value: RecordKind.text, label: Text('نص')),
                  ButtonSegment<RecordKind>(value: RecordKind.uri, label: Text('رابط')),
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
                textDirection: _kind == RecordKind.uri ? TextDirection.ltr : TextDirection.rtl,
                keyboardType: _kind == RecordKind.uri ? TextInputType.url : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _kind == RecordKind.uri ? 'الرابط' : 'النص',
                  hintText: _kind == RecordKind.uri ? 'https://example.com' : 'اكتب البيانات التي تريد تخزينها',
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
                    ? 'في انتظار الوسم…'
                    : (_mode == NfcMode.read ? 'بدء القراءة' : 'بدء الكتابة'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'قرّب الجزء العلوي من الجهاز من الوسم دون لمسه، ويُفضّل إزالة الغطاء السميك.',
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
              Text('محتويات الوسم', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._records.map((DecodedRecord record) => _recordTile(theme, record)),
            ],
            const SizedBox(height: 24),
            Text(
              'ملاحظة: على iOS لا تعمل قراءة NFC إلا إذا كان التطبيق موقّعًا بحساب Apple Developer يملك صلاحية NFC (حساب مدفوع). '
              'التوقيع المجاني لا يمنح هذه الصلاحية.',
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
      title = 'جارٍ فحص دعم NFC…';
      subtitle = 'تحقّق من أن الجهاز يدعم NFC.';
    } else if (_availabilityError != null) {
      color = colors.error;
      icon = Icons.error_outline_rounded;
      title = 'NFC غير متاح على هذه المنصة';
      subtitle = _availabilityError!;
    } else if (_availability == NfcAvailability.enabled) {
      color = const Color(0xFF2ECC71);
      title = 'NFC جاهز';
      subtitle = 'يمكنك القراءة والكتابة على وسوم NDEF.';
    } else if (_availability == NfcAvailability.disabled) {
      color = Colors.orangeAccent;
      icon = Icons.sensors_off_rounded;
      title = 'NFC مغلق';
      subtitle = 'فعّل NFC من إعدادات الجهاز ثم أعد المحاولة.';
    } else {
      color = colors.error;
      icon = Icons.sensors_off_rounded;
      title = 'هذا الجهاز لا يدعم NFC';
      subtitle = 'جرّب جهازًا آخر يدعم قراءة الوسوم.';
    }

    return Card(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
      _infoRow('قابل للكتابة', tag.writable ? 'نعم' : 'لا (مقفل)'),
      _infoRow('سعة الوسم', tag.capacity > 0 ? '${tag.capacity} بايت' : 'غير معروفة'),
      if (tag.messageSize != null) _infoRow('حجم الرسالة', '${tag.messageSize} بايت'),
    ];
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('تفاصيل الوسم', style: theme.textTheme.titleMedium),
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
