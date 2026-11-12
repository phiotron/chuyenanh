import 'dart:io';
import 'dart:typed_data';

import 'package:office_reader/office_reader.dart' as office;
import 'package:pdf_layout/pdf_layout.dart' show LayoutPage;

import '../../../engines/convert/convert_engine.dart';
import '../../../engines/ocr/ocr_engine.dart';
import '../../../engines/pdf/pdf_render_engine.dart';
import '../ocr/ocr_to_layout.dart';
import 'pdf_convert_engine.dart';

/// [ConvertEngine] bọc [PdfConvertEngine]: PDF → TXT/DOCX/XLSX có thêm OCR cho trang KHÔNG có chữ
/// (PDF quét ảnh). Trang có chữ thật dùng chữ thật. Các chiều → PDF chuyển thẳng cho [inner].
///
/// OCR (ML Kit, plugin native) và render trang (pdfx) chạy ở isolate chính nhưng bất đồng bộ nên
/// không chặn UI; trích chữ và ghi file vẫn chạy nền như cũ.
class OcrPdfConvertEngine implements ConvertEngine {
  OcrPdfConvertEngine({
    required this.inner,
    required this.render,
    required this.ocr,
    required this.scriptProvider,
    required this.tempDir,
    this.targetDpi = 200,
  });

  final PdfConvertEngine inner;
  final PdfRenderEngine render;
  final OcrEngine ocr;

  /// Hệ chữ OCR tại thời điểm chuyển (người dùng chọn hoặc theo ngôn ngữ app).
  final OcrScript Function() scriptProvider;

  /// Thư mục chứa ảnh trang tạm (được tạo, và xoá sau khi xong).
  final String tempDir;
  final double targetDpi;

  // Phân bổ tiến độ: trích chữ 0–0.1, OCR 0.1–0.9, ghi file 0.9–1.
  static const _extractShare = 0.1;
  static const _ocrShare = 0.8;

  Future<List<LayoutPage>> _pagesWithOcr(
    String inputPath,
    String? password,
    ProgressCallback? onProgress,
    CancelToken? token,
  ) async {
    final pages = await inner.extractPages(
      inputPath,
      password: password,
      onProgress: (p) => onProgress?.call(p * _extractShare),
      cancelToken: token,
    );
    final blank = [for (final p in pages) if (p.lines.isEmpty) p.index];
    if (blank.isEmpty) return pages;

    final out = [...pages];
    final work = await Directory(tempDir).create(recursive: true).then((d) => d.createTemp('pdfocr_'));
    PdfRenderDocument? doc;
    try {
      doc = await render.openFile(inputPath, password: password);
      final script = scriptProvider();
      for (var k = 0; k < blank.length; k++) {
        token?.throwIfCancelled();
        final i = blank[k];
        if (i >= doc.pageCount) continue;
        final size = await doc.pageSize(i);
        final dpi = ocrRenderDpi(size.width, size.height, targetDpi: targetDpi);
        final Uint8List png = await doc.renderPage(i, dpi: dpi, cancelToken: token);
        token?.throwIfCancelled();
        final file = File('${work.path}${Platform.pathSeparator}p$i.png');
        await file.writeAsBytes(png, flush: true);
        final result = await ocr.recognize(file.path, script);
        try {
          await file.delete();
        } catch (_) {}
        out[i] = ocrResultToLayoutPage(
          result,
          pageIndex: i,
          pageWidth: size.width,
          pageHeight: size.height,
        );
        onProgress?.call(_extractShare + _ocrShare * (k + 1) / blank.length);
      }
    } finally {
      await doc?.close();
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
    return out;
  }

  Future<String> _pdfTo(
    PdfTextTarget target,
    String inputPath,
    String outputPath,
    String? password,
    ProgressCallback? onProgress,
    CancelToken? token,
  ) async {
    final pages = await _pagesWithOcr(inputPath, password, onProgress, token);
    return inner.writePages(
      target,
      pages,
      outputPath,
      onProgress: (p) => onProgress?.call(_extractShare + _ocrShare + 0.1 * p),
      cancelToken: token,
    );
  }

  @override
  Future<String> pdfToText(String inputPath, String outputPath,
          {String? password, ProgressCallback? onProgress, CancelToken? cancelToken}) =>
      _pdfTo(PdfTextTarget.text, inputPath, outputPath, password, onProgress, cancelToken);

  @override
  Future<String> pdfToDocx(String inputPath, String outputPath,
          {String? password, ProgressCallback? onProgress, CancelToken? cancelToken}) =>
      _pdfTo(PdfTextTarget.docx, inputPath, outputPath, password, onProgress, cancelToken);

  @override
  Future<String> pdfToXlsx(String inputPath, String outputPath,
          {String? password, ProgressCallback? onProgress, CancelToken? cancelToken}) =>
      _pdfTo(PdfTextTarget.xlsx, inputPath, outputPath, password, onProgress, cancelToken);

  @override
  Future<String> pdfToCsv(String inputPath, String outputPath,
          {String? password, ProgressCallback? onProgress, CancelToken? cancelToken}) =>
      _pdfTo(PdfTextTarget.csv, inputPath, outputPath, password, onProgress, cancelToken);

  // ---- Chiều → PDF: không cần OCR.

  @override
  Future<String> textToPdf(String text, String outputPath,
          {ToPdfOptions options = const ToPdfOptions(),
          ProgressCallback? onProgress,
          CancelToken? cancelToken}) =>
      inner.textToPdf(text, outputPath,
          options: options, onProgress: onProgress, cancelToken: cancelToken);

  @override
  Future<String> txtFileToPdf(String inputPath, String outputPath,
          {ToPdfOptions options = const ToPdfOptions(),
          ProgressCallback? onProgress,
          CancelToken? cancelToken}) =>
      inner.txtFileToPdf(inputPath, outputPath,
          options: options, onProgress: onProgress, cancelToken: cancelToken);

  @override
  Future<String> docxToPdf(String inputPath, String outputPath,
          {ToPdfOptions options = const ToPdfOptions(),
          ProgressCallback? onProgress,
          CancelToken? cancelToken}) =>
      inner.docxToPdf(inputPath, outputPath,
          options: options, onProgress: onProgress, cancelToken: cancelToken);

  @override
  Future<String> xlsxToPdf(String inputPath, String outputPath,
          {ToPdfOptions options = const ToPdfOptions(),
          ProgressCallback? onProgress,
          CancelToken? cancelToken}) =>
      inner.xlsxToPdf(inputPath, outputPath,
          options: options, onProgress: onProgress, cancelToken: cancelToken);

  @override
  Future<String> tableToPdf(office.XlsxWorkbook workbook, String outputPath,
          {ToPdfOptions options = const ToPdfOptions(),
          ProgressCallback? onProgress,
          CancelToken? cancelToken}) =>
      inner.tableToPdf(workbook, outputPath,
          options: options, onProgress: onProgress, cancelToken: cancelToken);
}
