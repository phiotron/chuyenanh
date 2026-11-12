/// Mọi path route của app (hợp đồng mục 2.1). Agent dùng, không đổi.
///
/// Điều hướng: `context.push(Routes.merge, extra: path)`. Kiểu `extra` ghi ở từng hằng.
abstract final class Routes {
  // --- documents ---
  /// Trang chủ.
  static const home = '/';
  static const search = '/search';
  static const recents = '/recents';
  static const favorites = '/favorites';

  // --- image_to_pdf ---
  static const imageToPdf = '/image-to-pdf';

  // --- reader ---
  /// `extra: OpenFileArgs`.
  static const pdfReader = '/reader';

  /// `extra: String?` (path PDF, null = chọn file).
  static const pdfToImage = '/pdf-to-image';

  // --- pdf_tools — `extra: String?` (path PDF đầu vào, null = chọn file) ---
  static const merge = '/tools/merge';
  static const split = '/tools/split';
  static const organize = '/tools/organize';
  static const lock = '/tools/lock';
  static const unlock = '/tools/unlock';
  static const watermark = '/tools/watermark';
  static const createBlank = '/tools/create-blank';
  static const compress = '/tools/compress';
  static const pageNumbers = '/tools/page-numbers';
  static const insertPages = '/tools/insert-pages';

  // --- editor — `extra: String` (path PDF) ---
  static const annotate = '/edit/annotate';
  static const sign = '/edit/sign';
  static const fillForm = '/edit/fill-form';

  // --- convert — `extra: String?` (path đầu vào, null = chọn file / gõ chữ) ---
  static const textToPdf = '/convert/text-to-pdf';
  static const wordToPdf = '/convert/word-to-pdf';
  static const excelToPdf = '/convert/excel-to-pdf';
  static const csvToPdf = '/convert/csv-to-pdf';
  static const pdfToText = '/convert/pdf-to-text';
  static const pdfToWord = '/convert/pdf-to-word';
  static const pdfToExcel = '/convert/pdf-to-excel';
  static const pdfToCsv = '/convert/pdf-to-csv';

  // --- ppt_convert — `extra: String?` (path đầu vào, null = chọn file) ---
  static const pptToPdf = '/convert/ppt-to-pdf';
  static const pdfToPpt = '/convert/pdf-to-ppt';

  // --- reading — `extra: OpenFileArgs` (PDF đang đọc) ---
  /// Chế độ đọc dàn lại chữ (+ đọc to, dịch).
  static const reflow = '/reader/reflow';

  // --- office_viewer — `extra: String` (path) ---
  static const docxViewer = '/view/docx';
  static const xlsxViewer = '/view/xlsx';
  static const txtViewer = '/view/txt';

  // --- office_pptx — `extra: String` (path) ---
  static const pptxViewer = '/view/pptx';

  // --- scanner ---
  static const scanner = '/scanner';

  // --- id_card / qr — không `extra` ---
  /// Quét 2 mặt thẻ (CCCD, danh thiếp…) lên 1 trang.
  static const idCard = '/scanner/id-card';
  static const qrScan = '/qr';

  // --- settings ---
  static const settings = '/settings';
  static const language = '/settings/language';
  static const about = '/settings/about';
}
