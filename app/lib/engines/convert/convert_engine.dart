import 'package:office_reader/office_reader.dart' show XlsxWorkbook;

import '../../core/utils/cancel_token.dart';
import '../../core/utils/page_size.dart';

export '../../core/utils/cancel_token.dart' show CancelToken, ProgressCallback;
export '../../core/utils/page_size.dart' show PageSizeOption;

/// Tuỳ chọn xuất PDF từ văn bản / Office.
class ToPdfOptions {
  const ToPdfOptions({
    this.pageSize = PageSizeOption.a4,
    this.landscape = false,
    this.fontSize = 12,
    this.marginPoints = 40,
  });

  final PageSizeOption pageSize;
  final bool landscape;

  /// Cỡ chữ cơ sở (point) cho văn bản thuần.
  final double fontSize;
  final double marginPoints;
}

/// Chuyển đổi. Mọi hàm ghi an toàn ra [outputPath], trả về path kết quả, báo tiến độ 0→1,
/// kiểm [CancelToken]. Font Noto lấy từ `assets/fonts/` (thiếu file → rơi về font chuẩn + log).
/// Lỗi: `CorruptFile`, `UnsupportedFormat`, `PasswordRequired`, `WrongPassword`, `Cancelled`.
abstract interface class ConvertEngine {
  /// Chữ gõ / nội dung TXT → PDF (tự xuống dòng, phân trang).
  Future<String> textToPdf(
    String text,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// File .txt → PDF (tự nhận UTF-8 / UTF-16).
  Future<String> txtFileToPdf(
    String inputPath,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// .docx → PDF (đoạn, heading, bảng, ảnh — gần đúng).
  Future<String> docxToPdf(
    String inputPath,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// .xlsx → PDF (mỗi sheet thành bảng `PdfGrid`).
  Future<String> xlsxToPdf(
    String inputPath,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// Bảng đã đọc sẵn (XLSX hoặc CSV) → PDF, cùng cách vẽ với [xlsxToPdf].
  Future<String> tableToPdf(
    XlsxWorkbook workbook,
    String outputPath, {
    ToPdfOptions options = const ToPdfOptions(),
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// PDF → .txt (UTF-8), trang cách nhau bằng dòng trống.
  Future<String> pdfToText(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// PDF → .docx (gom dòng thành đoạn, đoán heading). Không giữ bố cục gốc.
  Future<String> pdfToDocx(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// PDF → .xlsx (đoán bảng theo toạ độ chữ). Không giữ bố cục gốc.
  Future<String> pdfToXlsx(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });

  /// PDF → .csv (cùng cách đoán bảng với [pdfToXlsx], ghi UTF-8 BOM cho Excel).
  Future<String> pdfToCsv(
    String inputPath,
    String outputPath, {
    String? password,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  });
}
