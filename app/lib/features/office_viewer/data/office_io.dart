import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:office_reader/office_reader.dart' as rd;

import '../../../core/errors/app_error.dart';
import '../../../core/utils/doc_type.dart';
import 'csv_reader.dart';

/// Chạy [body] trong isolate; mọi lỗi được đổi thành [AppError] ngay trong isolate
/// (để chắc chắn gửi về được).
Future<T> runParsing<T>(T Function() body) async {
  try {
    return await Isolate.run(() {
      try {
        return body();
      } on rd.OfficeFormatException catch (e) {
        throw CorruptFile(e.message);
      } on AppError {
        rethrow;
      } on FileSystemException catch (e) {
        final code = e.osError?.errorCode;
        if (code == null || code == 2 || code == 3) {
          throw const CorruptFile('not found');
        }
        throw AppError.from(e);
      } catch (e) {
        throw CorruptFile(e.toString());
      }
    });
  } on AppError {
    rethrow;
  } catch (e) {
    throw AppError.from(e);
  }
}

/// Đọc + parse DOCX thành model `office_reader`.
Future<rd.DocxDocument> readDocxFile(String path) =>
    runParsing(() => rd.readDocx(File(path).readAsBytesSync()));

Future<rd.DocxDocument> readDocxBytes(Uint8List bytes) =>
    runParsing(() => rd.readDocx(bytes));

Future<rd.XlsxWorkbook> readXlsxFile(String path) =>
    runParsing(() => rd.readXlsx(File(path).readAsBytesSync()));

Future<rd.XlsxWorkbook> readXlsxBytes(Uint8List bytes) =>
    runParsing(() => rd.readXlsx(bytes));

/// Đọc bảng từ `.xlsx` hoặc `.csv` (trình xem XLSX dùng chung).
Future<SpreadsheetContent> readSpreadsheetFile(String path) =>
    extensionOf(path) == 'csv'
    ? runParsing(() => readCsvFileSync(path))
    : runParsing(
        () => SpreadsheetContent(rd.readXlsx(File(path).readAsBytesSync())),
      );
