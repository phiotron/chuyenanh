import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:office_reader/office_reader.dart' as rd;
import 'package:path/path.dart' as p;

import '../../../core/errors/app_error.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/doc_type.dart';
import '../../../core/widgets/widgets.dart';
import '../data/csv_reader.dart';
import '../data/office_io.dart';
import '../data/text_decoder.dart';
import '../widgets/docx_view.dart';
import '../widgets/office_common.dart';
import '../widgets/txt_viewer_page.dart';
import '../widgets/xlsx_view.dart';

final txtContentProvider = FutureProvider.autoDispose
    .family<DecodedText, String>((ref, path) => readTextFile(path));

final docxContentProvider = FutureProvider.autoDispose
    .family<rd.DocxDocument, String>((ref, path) => readDocxFile(path));

final xlsxContentProvider = FutureProvider.autoDispose
    .family<SpreadsheetContent, String>(
      (ref, path) => readSpreadsheetFile(path),
    );

/// Khung chờ / lỗi chung của 3 màn xem: thanh tiêu đề màu theo loại file.
class _LoadScaffold extends StatelessWidget {
  const _LoadScaffold({required this.path, required this.category, this.body});

  final String path;
  final DocCategory category;

  /// null = đang nạp (vòng xoay cùng màu loại file).
  final Widget? body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: OfficeViewerAppBar(category: category, title: p.basename(path)),
    body:
        body ??
        Center(
          child: CircularProgressIndicator(color: officeHeaderColor(category)),
        ),
  );
}

Widget _error(BuildContext context, Object e, VoidCallback retry) {
  final msg = appErrorMessage(context, AppError.from(e));
  return EmptyState(
    icon: Symbols.error_rounded,
    title: msg,
    actionLabel: context.l10n.core_retry,
    onAction: retry,
  );
}

class TxtViewerScreen extends ConsumerWidget {
  const TxtViewerScreen({super.key, required this.path});
  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = this.path;
    if (path == null) return const Scaffold(body: SizedBox.shrink());
    final async = ref.watch(txtContentProvider(path));
    return async.when(
      data: (c) => TxtViewerPage(path: path, content: c),
      loading: () => _LoadScaffold(path: path, category: DocCategory.txt),
      error: (e, _) => _LoadScaffold(
        path: path,
        category: DocCategory.txt,
        body: _error(
          context,
          e,
          () => ref.invalidate(txtContentProvider(path)),
        ),
      ),
    );
  }
}

class DocxViewerScreen extends ConsumerWidget {
  const DocxViewerScreen({super.key, required this.path});
  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = this.path;
    if (path == null) return const Scaffold(body: SizedBox.shrink());
    final async = ref.watch(docxContentProvider(path));
    return async.when(
      data: (d) => DocxViewerPage(path: path, document: d),
      loading: () => _LoadScaffold(path: path, category: DocCategory.doc),
      error: (e, _) => _LoadScaffold(
        path: path,
        category: DocCategory.doc,
        body: _error(
          context,
          e,
          () => ref.invalidate(docxContentProvider(path)),
        ),
      ),
    );
  }
}

class XlsxViewerScreen extends ConsumerWidget {
  const XlsxViewerScreen({super.key, required this.path});
  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = this.path;
    if (path == null) return const Scaffold(body: SizedBox.shrink());
    final category = docTypeFromPath(path).category ?? DocCategory.xls;
    final async = ref.watch(xlsxContentProvider(path));
    return async.when(
      data: (c) => XlsxViewerPage(
        path: path,
        workbook: c.workbook,
        truncated: c.truncated,
      ),
      loading: () => _LoadScaffold(path: path, category: category),
      error: (e, _) => _LoadScaffold(
        path: path,
        category: category,
        body: _error(
          context,
          e,
          () => ref.invalidate(xlsxContentProvider(path)),
        ),
      ),
    );
  }
}
