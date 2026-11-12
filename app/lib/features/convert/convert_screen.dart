import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/errors/app_error.dart';
import '../../core/l10n/l10n.dart';
import '../../core/navigation/open_document.dart';
import '../../core/platform/app_platform.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_paths.dart';
import '../../core/utils/output_directory.dart';
import '../../core/widgets/widgets.dart';
import '../../data/settings/settings_providers.dart';
import '../../engines/convert/convert_engine.dart';
import '../office_viewer/data/office_io.dart';
import 'convert_providers.dart';
import 'engine/pdf_convert_engine.dart' show isNoTextError;
import 'text/text_decoder.dart';

/// Tám kiểu chuyển đổi của feature (mỗi kiểu một route).
enum ConvertMode {
  textToPdf(['txt'], 'pdf'),
  wordToPdf(['docx'], 'pdf'),
  excelToPdf(['xlsx'], 'pdf'),
  csvToPdf(['csv'], 'pdf'),
  pdfToText(['pdf'], 'txt'),
  pdfToWord(['pdf'], 'docx'),
  pdfToExcel(['pdf'], 'xlsx'),
  pdfToCsv(['pdf'], 'csv');

  const ConvertMode(this.inputExtensions, this.outputExtension);
  final List<String> inputExtensions;
  final String outputExtension;

  bool get toPdf => outputExtension == 'pdf';
  bool get fromPdf => inputExtensions.single == 'pdf';

  /// PDF → Word/Excel/CSV: cảnh báo không giữ bố cục.
  bool get rebuildsLayout =>
      this == pdfToWord || this == pdfToExcel || this == pdfToCsv;
}

String _modeTitle(BuildContext context, ConvertMode mode) {
  final l = context.l10n;
  return switch (mode) {
    ConvertMode.textToPdf => l.conv_textToPdf,
    ConvertMode.wordToPdf => l.conv_wordToPdf,
    ConvertMode.excelToPdf => l.conv_excelToPdf,
    ConvertMode.csvToPdf => l.conv_csvToPdf,
    ConvertMode.pdfToText => l.conv_pdfToText,
    ConvertMode.pdfToWord => l.conv_pdfToWord,
    ConvertMode.pdfToExcel => l.conv_pdfToExcel,
    ConvertMode.pdfToCsv => l.conv_pdfToCsv,
  };
}

class ConvertScreen extends ConsumerStatefulWidget {
  const ConvertScreen({super.key, required this.mode, this.initialPath});

  final ConvertMode mode;
  final String? initialPath;

  @override
  ConsumerState<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends ConsumerState<ConvertScreen> {
  final _text = TextEditingController();
  String? _inputPath;
  String? _resultPath;
  PageSizeOption? _pageSize;
  bool _landscape = false;
  double _fontSize = 12;
  double _margin = 40;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath;
    if (initial != null) {
      if (widget.mode == ConvertMode.textToPdf) {
        _loadTxt(initial);
      } else {
        _inputPath = initial;
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadTxt(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _text.text = decodeTextBytes(bytes);
        _inputPath = path;
      });
    } catch (e) {
      _showError(AppError.from(e));
    }
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: widget.mode.inputExtensions,
    );
    final path = file?.path;
    if (path == null || !mounted) return;
    if (widget.mode == ConvertMode.textToPdf) {
      await _loadTxt(path);
    } else {
      setState(() {
        _inputPath = path;
        _resultPath = null;
      });
    }
  }

  void _showError(AppError e) {
    if (!mounted || e is Cancelled) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(appErrorMessage(context, e))),
    );
  }

  ToPdfOptions get _options => ToPdfOptions(
        pageSize: _pageSize ?? ref.read(settingsProvider).defaultPageSize,
        landscape: _landscape,
        fontSize: _fontSize,
        marginPoints: _margin,
      );

  Future<void> _convert() async {
    final mode = widget.mode;
    final l = context.l10n;
    if (mode == ConvertMode.textToPdf && _text.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.conv_emptyText)));
      return;
    }
    if (mode != ConvertMode.textToPdf && _inputPath == null) {
      await _pick();
      if (_inputPath == null) return;
    }
    setState(() {
      _busy = true;
      _resultPath = null;
    });
    final engine = ref.read(convertEngineProvider);
    try {
      final dir = await ref.read(outputDirectoryProvider.future);
      final base = _inputPath != null
          ? baseNameWithoutExtension(_inputPath!)
          : 'Text';
      final out = await uniqueOutputPath(dir, base, mode.outputExtension);
      String? password;
      String? wrongHint;
      while (true) {
        if (!mounted) return;
        final progress = showProgressDialog(context, title: l.core_processing);
        try {
          final result = await _run(engine, mode, out, password, progress);
          progress.close();
          if (!mounted) return;
          setState(() => _resultPath = result);
          return;
        } on PasswordRequired {
          progress.close();
        } on WrongPassword {
          progress.close();
          wrongHint = l.core_errorWrongPassword;
        } catch (_) {
          progress.close();
          rethrow;
        }
        if (!mounted) return;
        password = await showPasswordDialog(
          context,
          message: l.core_passwordDialogMessage(p.basename(_inputPath!)),
          errorText: wrongHint,
        );
        if (password == null) return;
      }
    } on AppError catch (e) {
      _handle(e);
    } catch (e) {
      _handle(AppError.from(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handle(AppError e) {
    if (!mounted) return;
    if (isNoTextError(e)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.conv_noTextFound)));
    } else {
      _showError(e);
    }
  }

  Future<String> _run(
    ConvertEngine engine,
    ConvertMode mode,
    String out,
    String? password,
    ProgressDialogController progress,
  ) async {
    void onProgress(double v) => progress.update(v);
    final token = progress.cancelToken;
    switch (mode) {
      case ConvertMode.textToPdf:
        return engine.textToPdf(_text.text, out,
            options: _options, onProgress: onProgress, cancelToken: token);
      case ConvertMode.wordToPdf:
        return engine.docxToPdf(_inputPath!, out,
            options: _options, onProgress: onProgress, cancelToken: token);
      case ConvertMode.excelToPdf:
        return engine.xlsxToPdf(_inputPath!, out,
            options: _options, onProgress: onProgress, cancelToken: token);
      case ConvertMode.csvToPdf:
        // CSV được đọc bằng đúng trình đọc của màn xem bảng (tự nhận dấu phân cách,
        // bảng mã), rồi vẽ PDF như một bảng Excel.
        final content = await readSpreadsheetFile(_inputPath!);
        if (content.truncated && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.office_truncated)),
          );
        }
        token.throwIfCancelled();
        return engine.tableToPdf(content.workbook, out,
            options: _options, onProgress: onProgress, cancelToken: token);
      case ConvertMode.pdfToText:
        return engine.pdfToText(_inputPath!, out,
            password: password, onProgress: onProgress, cancelToken: token);
      case ConvertMode.pdfToWord:
        return engine.pdfToDocx(_inputPath!, out,
            password: password, onProgress: onProgress, cancelToken: token);
      case ConvertMode.pdfToExcel:
        return engine.pdfToXlsx(_inputPath!, out,
            password: password, onProgress: onProgress, cancelToken: token);
      case ConvertMode.pdfToCsv:
        return engine.pdfToCsv(_inputPath!, out,
            password: password, onProgress: onProgress, cancelToken: token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final mode = widget.mode;
    final t = context.tokens;
    final pageSize = _pageSize ?? ref.watch(settingsProvider).defaultPageSize;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text(_modeTitle(context, mode))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 1. Đầu vào: ô gõ chữ (Văn bản sang PDF) hoặc thẻ chọn file.
          if (mode == ConvertMode.textToPdf)
            _Block(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _text,
                    minLines: 8,
                    maxLines: 14,
                    style: TextStyle(fontSize: 15, height: 1.5, color: t.text),
                    decoration: InputDecoration(
                      hintText: l.conv_textHint,
                      hintStyle: TextStyle(color: t.textMuted),
                      filled: true,
                      fillColor: t.input,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Symbols.description_rounded, size: 20),
                    label: Text(l.conv_loadTxt),
                  ),
                ],
              ),
            )
          else
            _FileCard(
              path: _inputPath,
              placeholderExtension: mode.inputExtensions.single,
              title: _inputPath == null
                  ? l.conv_chooseFile
                  : l.conv_chosenFile(p.basename(_inputPath!)),
              changeTooltip: l.core_selectFile,
              onTap: _busy ? null : _pick,
            ),
          // 2. Cảnh báo không giữ bố cục (PDF sang Word/Excel).
          if (mode.rebuildsLayout) ...[
            const SizedBox(height: 12),
            _Notice(text: l.conv_layoutNotice),
          ],
          // 3. Mọi chế độ từ PDF: thông báo OCR (chỉ chữ Latin: Anh, Việt).
          if (mode.fromPdf) ...[
            const SizedBox(height: 12),
            _Notice(text: l.conv_ocrNotice),
          ],
          // 4. Mọi chế độ sang PDF: mục Tuỳ chọn.
          if (mode.toPdf) ...[
            _SectionLabel(l.conv_options),
            CardSection(
              children: [
                _OptionRow(
                  label: l.conv_pageSize,
                  child: SegmentedButton<PageSizeOption>(
                    style: _pillSegmentStyle(context),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: PageSizeOption.a4, label: Text('A4')),
                      ButtonSegment(value: PageSizeOption.letter, label: Text('Letter')),
                    ],
                    selected: {pageSize == PageSizeOption.letter ? PageSizeOption.letter : PageSizeOption.a4},
                    onSelectionChanged: (s) => setState(() => _pageSize = s.single),
                  ),
                ),
                _OptionRow(
                  label: l.conv_orientation,
                  child: SegmentedButton<bool>(
                    style: _pillSegmentStyle(context),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: false, label: Text(l.conv_portrait)),
                      ButtonSegment(value: true, label: Text(l.conv_landscape)),
                    ],
                    selected: {_landscape},
                    onSelectionChanged: (s) => setState(() => _landscape = s.single),
                  ),
                ),
                if (mode == ConvertMode.textToPdf)
                  _SliderRow(
                    label: l.conv_fontSize,
                    value: _fontSize,
                    min: 8,
                    max: 24,
                    onChanged: (v) => setState(() => _fontSize = v),
                  ),
                _SliderRow(
                  label: l.conv_margin,
                  value: _margin,
                  min: 0,
                  max: 72,
                  onChanged: (v) => setState(() => _margin = v),
                ),
              ],
            ),
          ],
          // 5. Nút chính.
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _convert,
            child: Text(l.conv_convert),
          ),
          // 6. Thẻ kết quả ngay trong màn.
          if (_resultPath != null) ...[
            const SizedBox(height: 20),
            _ResultCard(path: _resultPath!),
          ],
        ],
      ),
    );
  }
}

/// Kiểu viên cho [SegmentedButton]: đoạn đang chọn nền đỏ chủ đạo chữ trắng, còn lại nền `surface2`.
ButtonStyle _pillSegmentStyle(BuildContext context) {
  final t = context.tokens;
  return SegmentedButton.styleFrom(
    backgroundColor: t.surface2,
    foregroundColor: t.text,
    selectedBackgroundColor: AppColors.primary,
    selectedForegroundColor: Colors.white,
    side: BorderSide.none,
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );
}

/// Khối nền `surface` bo 20, không bóng.
class _Block extends StatelessWidget {
  const _Block({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: context.tokens.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

/// Nhãn mục 13/w700 màu phụ, đặt trên mỗi khối.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.tokens.textMuted,
      ),
    ),
  );
}

/// Thẻ chọn file: icon loại file + tên + nút đổi file; bấm cả thẻ cũng mở bộ chọn.
class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.path,
    required this.placeholderExtension,
    required this.title,
    required this.changeTooltip,
    required this.onTap,
  });

  final String? path;
  final String placeholderExtension;
  final String title;
  final String changeTooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              FileTypeIcon.forPath(path ?? 'x.$placeholderExtension', size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
              IconButton(
                tooltip: changeTooltip,
                onPressed: onTap,
                icon: Icon(Symbols.folder_open_rounded, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Khung thông báo: nền `surface2` bo 16, icon ⓘ màu phụ.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.info_rounded, size: 20, color: t.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Một dòng tuỳ chọn trong thẻ: nhãn bên trái, điều khiển bên phải.
class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.tokens.text,
            ),
          ),
        ),
        const SizedBox(width: 8),
        child,
      ],
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: t.text),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              label: value.round().toString(),
              activeColor: AppColors.primary,
              inactiveColor: AppColors.primary.withValues(alpha: 0.16),
              thumbColor: AppColors.primary,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              value.round().toString(),
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Màu xanh "xong" của dấu ✓ (màu XLS trong bảng loại file).
const _successGreen = Color(0xFF43A047);

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final canOpen = routeForDocument(path) != null;
    final share = OutlinedButton.icon(
      onPressed: () =>
          SharePlus.instance.share(
            ShareParams(
              files: [XFile(path)],
              sharePositionOrigin: defaultShareOrigin(),
            ),
          ),
      icon: const Icon(Symbols.share_rounded, size: 20),
      label: Text(l.core_share, overflow: TextOverflow.ellipsis),
    );
    return _Block(
      key: const Key('conv_result'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _successGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Symbols.check_rounded, color: _successGreen, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.conv_doneTitle,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // SelectionArea + Text (không dùng SelectableText): chọn được chữ mà vẫn là widget [Text],
          // integration test đọc đường dẫn file kết quả qua `tester.widget<Text>`.
          SelectionArea(
            child: Text(
              l.conv_savedAs(path),
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (canOpen) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      try {
                        await openDocument(context, path);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(appErrorMessage(context, AppError.from(e)))),
                          );
                        }
                      }
                    },
                    icon: const Icon(Symbols.open_in_new_rounded, size: 20),
                    label: Text(l.core_open, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: share),
            ],
          ),
        ],
      ),
    );
  }
}
