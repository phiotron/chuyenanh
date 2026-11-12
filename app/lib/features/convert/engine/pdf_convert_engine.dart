import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:office_reader/office_reader.dart' as office;
import 'package:pdf_layout/pdf_layout.dart' show LayoutPage, detectSheets;

import '../../../core/errors/app_error.dart';
import '../../../core/utils/file_paths.dart';
import '../../../engines/convert/convert_engine.dart';
import '../text/text_decoder.dart';
import 'background.dart';
import 'csv_builder.dart';
import 'font_set.dart';
import 'pdf_builders.dart';
import 'pdf_extract.dart';

/// Thiếu chữ để chuyển (PDF quét ảnh…) — bọc trong [Unknown] để UI nhận ra.
bool isNoTextError(Object e) => e is Unknown && e.cause is NoTextFoundException;

/// Định dạng đầu ra của PDF → văn bản / bảng.
enum PdfTextTarget { text, docx, xlsx, csv }

/// [ConvertEngine] dùng Syncfusion PDF/XlsIO + `office_reader` + `pdf_layout`.
///
/// [useIsolate] = false chạy ngay trong isolate hiện tại (nhanh cho test, không huỷ giữa chừng được).
class PdfConvertEngine implements ConvertEngine {
  const PdfConvertEngine({this.fontSource = const AssetFontSource(), this.useIsolate = true});

  final FontSource fontSource;
  final bool useIsolate;

  Future<T> _run<T>(
    BackgroundJob<T> job,
    ProgressCallback? onProgress,
    CancelToken? token,
  ) {
    if (useIsolate) {
      return runInBackground(job, onProgress: onProgress, cancelToken: token);
    }
    token?.throwIfCancelled();
    try {
      return Future.value(job((p) => onProgress?.call(p)));
    } catch (e) {
      return Future.error(e is AppError ? e : AppError.from(e));
    }
  }

  Future<String> _save(String outputPath, List<int> bytes) async {
    try {
      final f = await writeAtomically(outputPath, bytes);
      return f.path;
    } catch (e) {
      throw AppError.from(e);
    }
  }

  Future<Uint8List> _readInput(String path) async {
    final f = File(path);
    if (!await f.exists()) throw const CorruptFile('not found');
    try {
      return await f.readAsBytes();
    } catch (e) {
      throw AppError.from(e);
    }
  }

  Future<PdfFontSet> _fonts(String sampleText, {bool bold = true}) async =>
      PdfFontSet(await loadFontBytes(fontSource, facesFor(sampleText), needBold: bold));

  // ---------------------------------------------------------------- → PDF

  @override
  Future<String> textToPdf(
    String text,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final fontBytes = await loadFontBytes(fontSource, facesFor(text), needBold: false);
    cancelToken?.throwIfCancelled();
    final bytes = await _run<Uint8List>(
      (report) => buildTextPdf(text, options, PdfFontSet(fontBytes), report: report).bytes,
      onProgress,
      cancelToken,
    );
    onProgress?.call(1);
    return _save(outputPath, bytes);
  }

  @override
  Future<String> txtFileToPdf(
    String inputPath,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    return textToPdf(
      decodeTextBytes(raw),
      outputPath,
      options: options,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<String> docxToPdf(
    String inputPath,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    final doc = await _run<office.DocxDocument>((_) {
      try {
        return office.readDocx(raw);
      } on office.OfficeFormatException catch (e) {
        throw CorruptFile(e.toString());
      }
    }, null, cancelToken);
    onProgress?.call(0.15);
    final fonts = await _fonts(docxPlainText(doc));
    final fontBytes = fonts.bytes;
    final bytes = await _run<Uint8List>(
      (report) => buildDocxPdf(doc, options, PdfFontSet(fontBytes),
          report: (p) => report(0.15 + p * 0.85)).bytes,
      onProgress,
      cancelToken,
    );
    return _save(outputPath, bytes);
  }

  @override
  Future<String> xlsxToPdf(
    String inputPath,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    final wb = await _run<office.XlsxWorkbook>((_) {
      try {
        return office.readXlsx(raw);
      } on office.OfficeFormatException catch (e) {
        throw CorruptFile(e.toString());
      }
    }, null, cancelToken);
    onProgress?.call(0.15);
    return tableToPdf(wb, outputPath,
        options: options, onProgress: (p) => onProgress?.call(0.15 + p * 0.85), cancelToken: cancelToken);
  }

  @override
  Future<String> tableToPdf(
    office.XlsxWorkbook wb,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final fonts = await _fonts(xlsxPlainText(wb));
    final fontBytes = fonts.bytes;
    final bytes = await _run<Uint8List>(
      (report) => buildXlsxPdf(wb, options, PdfFontSet(fontBytes), report: report).bytes,
      onProgress,
      cancelToken,
    );
    onProgress?.call(1);
    return _save(outputPath, bytes);
  }

  // ---------------------------------------------------------------- PDF → (tách bước, cho OCR)

  /// Trích chữ thật của PDF thành các trang layout (trang ảnh có `lines` rỗng).
  /// Tiến độ 0→1 của bước trích.
  Future<List<LayoutPage>> extractPages(
    String inputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    return _run<List<LayoutPage>>(
      (report) => extractLayoutPages(raw, password: password, report: (p) => report(p / 0.8)),
      onProgress,
      cancelToken,
    );
  }

  /// Ghi [pages] ra [outputPath] theo [target]. Không có dòng chữ nào → `Unknown(NoTextFoundException)`.
  Future<String> writePages(
    PdfTextTarget target,
    List<LayoutPage> pages,
    String outputPath, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!hasAnyText(pages)) throw const Unknown(NoTextFoundException());
    final bytes = await _run<Uint8List>(
      (_) => switch (target) {
        PdfTextTarget.text => Uint8List.fromList(utf8.encode(layoutPagesToText(pages))),
        PdfTextTarget.docx => layoutPagesToDocx(pages),
        PdfTextTarget.xlsx => layoutPagesToXlsx(pages).bytes,
        PdfTextTarget.csv => csvBytes(csvFromSheets(detectSheets(pages))),
      },
      onProgress,
      cancelToken,
    );
    onProgress?.call(1);
    return _save(outputPath, bytes);
  }

  // ---------------------------------------------------------------- PDF →

  @override
  Future<String> pdfToText(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    final result = await _run<(String, bool)>((report) {
      final pages = extractLayoutPages(raw, password: password, report: report);
      return (layoutPagesToText(pages), hasAnyText(pages));
    }, onProgress, cancelToken);
    if (!result.$2) throw const Unknown(NoTextFoundException());
    onProgress?.call(1);
    return _save(outputPath, utf8.encode(result.$1));
  }

  @override
  Future<String> pdfToDocx(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    final result = await _run<(Uint8List, bool)>((report) {
      final pages = extractLayoutPages(raw, password: password, report: report);
      final ok = hasAnyText(pages);
      return (ok ? layoutPagesToDocx(pages) : Uint8List(0), ok);
    }, onProgress, cancelToken);
    if (!result.$2) throw const Unknown(NoTextFoundException());
    onProgress?.call(1);
    return _save(outputPath, result.$1);
  }

  @override
  Future<String> pdfToXlsx(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    final result = await _run<(Uint8List, bool)>((report) {
      final pages = extractLayoutPages(raw, password: password, report: report);
      final ok = hasAnyText(pages);
      return (ok ? layoutPagesToXlsx(pages).bytes : Uint8List(0), ok);
    }, onProgress, cancelToken);
    if (!result.$2) throw const Unknown(NoTextFoundException());
    onProgress?.call(1);
    return _save(outputPath, result.$1);
  }

  @override
  Future<String> pdfToCsv(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final raw = await _readInput(inputPath);
    final result = await _run<(Uint8List, bool)>((report) {
      final pages = extractLayoutPages(raw, password: password, report: report);
      final ok = hasAnyText(pages);
      return (ok ? csvBytes(csvFromSheets(detectSheets(pages))) : Uint8List(0), ok);
    }, onProgress, cancelToken);
    if (!result.$2) throw const Unknown(NoTextFoundException());
    onProgress?.call(1);
    return _save(outputPath, result.$1);
  }
}
