import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/db/app_database.dart';
import '../errors/app_error.dart';
import '../router/routes.dart';
import '../utils/doc_type.dart';
import 'open_file_args.dart';

export 'open_file_args.dart';

/// Route nội bộ cho [path]; `null` = mở bằng app ngoài (doc/xls/ppt) hoặc không hỗ trợ.
/// Hàm thuần — có unit test.
String? routeForDocument(String path) => switch (docTypeFromPath(path)) {
  DocType.pdf => Routes.pdfReader,
  DocType.docx => Routes.docxViewer,
  DocType.xlsx || DocType.csv => Routes.xlsxViewer,
  DocType.pptx => Routes.pptxViewer,
  DocType.txt => Routes.txtViewer,
  _ => null,
};

/// Mở file theo loại: pdf → reader, docx/xlsx/csv/pptx/txt → viewer tương ứng,
/// doc/xls/ppt → app ngoài (`open_filex`, chép vào cache trước). Ghi vào bảng `recents`.
///
/// Ném [UnsupportedFormat] nếu loại không hỗ trợ / không có app ngoài mở được,
/// [CorruptFile] nếu file không tồn tại.
Future<void> openDocument(
  BuildContext context,
  String path, {
  String? password,
}) async {
  if (!await File(path).exists()) throw const CorruptFile('not found');
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final type = docTypeFromPath(path);
  final route = routeForDocument(path);

  if (route != null) {
    await container.read(appDatabaseProvider).recentsDao.touch(path);
    if (!context.mounted) return;
    final Object extra = route == Routes.pdfReader
        ? OpenFileArgs(path, password: password)
        : path;
    await context.push(route, extra: extra);
    return;
  }

  if (type.isLegacyOffice) {
    await container.read(appDatabaseProvider).recentsDao.touch(path);
    final cacheDir = await getTemporaryDirectory();
    final copy = p.join(cacheDir.path, 'open_external', p.basename(path));
    await Directory(p.dirname(copy)).create(recursive: true);
    await File(path).copy(copy);
    final result = await OpenFilex.open(copy);
    if (result.type != ResultType.done) {
      throw UnsupportedFormat(extensionOf(path));
    }
    return;
  }
  throw UnsupportedFormat(extensionOf(path));
}
