import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../l10n/l10n.dart';
import '../router/routes.dart';

/// Nhóm công cụ (thứ tự hiển thị trong lưới Công cụ).
enum ToolGroup { create, convert, pdfTools, edit }

/// Đầu vào công cụ cần — feature documents dựa vào đây để mở picker trước hay không.
enum ToolInputType {
  /// Không cần file: push route không `extra`.
  none,

  /// Một PDF, route nhận `String?` — màn công cụ tự chọn file nếu null.
  pdf,

  /// Nhiều PDF (gộp): route nhận `String?` = file đầu tiên (nếu có).
  multiplePdf,

  /// Bắt buộc một PDF: người gọi chọn file trước rồi push `extra: String path`.
  pdfRequired,

  /// Một DOCX, route nhận `String?`.
  word,

  /// Một XLSX, route nhận `String?`.
  excel,

  /// Một CSV, route nhận `String?`.
  csv,

  /// Chữ gõ hoặc TXT, route nhận `String?`.
  text,

  /// Ảnh: màn tự chọn ảnh.
  images,
}

/// Mô tả một công cụ trong lưới / nút ＋.
@immutable
class ToolSpec {
  const ToolSpec({
    required this.id,
    required this.route,
    required this.icon,
    required this.labelKey,
    required this.group,
    required this.inputType,
  });

  /// Id ổn định (dùng làm key widget, analytics nội bộ).
  final String id;
  final String route;
  final IconData icon;

  /// Key ARB của tên công cụ (`core_tool...`). Lấy chữ: [toolLabel].
  final String labelKey;
  final ToolGroup group;
  final ToolInputType inputType;
}

/// Mọi công cụ của spec, theo thứ tự hiển thị.
const List<ToolSpec> allTools = [
  // Tạo PDF
  ToolSpec(
    id: 'imageToPdf',
    route: Routes.imageToPdf,
    icon: Symbols.photo_library_rounded,
    labelKey: 'core_toolImageToPdf',
    group: ToolGroup.create,
    inputType: ToolInputType.images,
  ),
  ToolSpec(
    id: 'scanner',
    route: Routes.scanner,
    icon: Symbols.document_scanner_rounded,
    labelKey: 'core_toolScanner',
    group: ToolGroup.create,
    inputType: ToolInputType.none,
  ),
  ToolSpec(
    id: 'textToPdf',
    route: Routes.textToPdf,
    icon: Symbols.text_fields_rounded,
    labelKey: 'core_toolTextToPdf',
    group: ToolGroup.create,
    inputType: ToolInputType.text,
  ),
  ToolSpec(
    id: 'createBlank',
    route: Routes.createBlank,
    icon: Symbols.note_add_rounded,
    labelKey: 'core_toolCreateBlank',
    group: ToolGroup.create,
    inputType: ToolInputType.none,
  ),
  ToolSpec(
    id: 'idCard',
    route: Routes.idCard,
    icon: Symbols.id_card_rounded,
    labelKey: 'core_toolIdCard',
    group: ToolGroup.create,
    inputType: ToolInputType.none,
  ),
  ToolSpec(
    id: 'qrScan',
    route: Routes.qrScan,
    icon: Symbols.qr_code_scanner_rounded,
    labelKey: 'core_toolQrScan',
    group: ToolGroup.create,
    inputType: ToolInputType.none,
  ),
  ToolSpec(
    id: 'pptToPdf',
    route: Routes.pptToPdf,
    icon: Symbols.slideshow_rounded,
    labelKey: 'core_toolPptToPdf',
    group: ToolGroup.create,
    inputType: ToolInputType.none,
  ),
  // Chuyển đổi
  ToolSpec(
    id: 'wordToPdf',
    route: Routes.wordToPdf,
    icon: Symbols.description_rounded,
    labelKey: 'core_toolWordToPdf',
    group: ToolGroup.convert,
    inputType: ToolInputType.word,
  ),
  ToolSpec(
    id: 'excelToPdf',
    route: Routes.excelToPdf,
    icon: Symbols.table_chart_rounded,
    labelKey: 'core_toolExcelToPdf',
    group: ToolGroup.convert,
    inputType: ToolInputType.excel,
  ),
  ToolSpec(
    id: 'csvToPdf',
    route: Routes.csvToPdf,
    icon: Symbols.table_view_rounded,
    labelKey: 'core_toolCsvToPdf',
    group: ToolGroup.convert,
    inputType: ToolInputType.csv,
  ),
  ToolSpec(
    id: 'pdfToImage',
    route: Routes.pdfToImage,
    icon: Symbols.imagesmode_rounded,
    labelKey: 'core_toolPdfToImage',
    group: ToolGroup.convert,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'pdfToText',
    route: Routes.pdfToText,
    icon: Symbols.notes_rounded,
    labelKey: 'core_toolPdfToText',
    group: ToolGroup.convert,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'pdfToWord',
    route: Routes.pdfToWord,
    icon: Symbols.article_rounded,
    labelKey: 'core_toolPdfToWord',
    group: ToolGroup.convert,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'pdfToExcel',
    route: Routes.pdfToExcel,
    icon: Symbols.grid_on_rounded,
    labelKey: 'core_toolPdfToExcel',
    group: ToolGroup.convert,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'pdfToCsv',
    route: Routes.pdfToCsv,
    icon: Symbols.table_rows_rounded,
    labelKey: 'core_toolPdfToCsv',
    group: ToolGroup.convert,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'pdfToPpt',
    route: Routes.pdfToPpt,
    icon: Symbols.co_present_rounded,
    labelKey: 'core_toolPdfToPpt',
    group: ToolGroup.convert,
    inputType: ToolInputType.pdf,
  ),
  // Công cụ PDF
  ToolSpec(
    id: 'merge',
    route: Routes.merge,
    icon: Symbols.call_merge_rounded,
    labelKey: 'core_toolMerge',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.multiplePdf,
  ),
  ToolSpec(
    id: 'split',
    route: Routes.split,
    icon: Symbols.call_split_rounded,
    labelKey: 'core_toolSplit',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'organize',
    route: Routes.organize,
    icon: Symbols.view_module_rounded,
    labelKey: 'core_toolOrganize',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'lock',
    route: Routes.lock,
    icon: Symbols.lock_rounded,
    labelKey: 'core_toolLock',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'unlock',
    route: Routes.unlock,
    icon: Symbols.lock_open_rounded,
    labelKey: 'core_toolUnlock',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'watermark',
    route: Routes.watermark,
    icon: Symbols.branding_watermark_rounded,
    labelKey: 'core_toolWatermark',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'compress',
    route: Routes.compress,
    icon: Symbols.compress_rounded,
    labelKey: 'core_toolCompress',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'pageNumbers',
    route: Routes.pageNumbers,
    icon: Symbols.format_list_numbered_rounded,
    labelKey: 'core_toolPageNumbers',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  ToolSpec(
    id: 'insertPages',
    route: Routes.insertPages,
    icon: Symbols.note_stack_add_rounded,
    labelKey: 'core_toolInsertPages',
    group: ToolGroup.pdfTools,
    inputType: ToolInputType.pdf,
  ),
  // Chỉnh sửa
  ToolSpec(
    id: 'annotate',
    route: Routes.annotate,
    icon: Symbols.ink_highlighter_rounded,
    labelKey: 'core_toolAnnotate',
    group: ToolGroup.edit,
    inputType: ToolInputType.pdfRequired,
  ),
  ToolSpec(
    id: 'sign',
    route: Routes.sign,
    icon: Symbols.signature_rounded,
    labelKey: 'core_toolSign',
    group: ToolGroup.edit,
    inputType: ToolInputType.pdfRequired,
  ),
  ToolSpec(
    id: 'fillForm',
    route: Routes.fillForm,
    icon: Symbols.edit_note_rounded,
    labelKey: 'core_toolFillForm',
    group: ToolGroup.edit,
    inputType: ToolInputType.pdfRequired,
  ),
];

/// Tìm công cụ theo id (null nếu không có).
ToolSpec? toolById(String id) {
  for (final t in allTools) {
    if (t.id == id) return t;
  }
  return null;
}

/// Tên công cụ theo ngôn ngữ hiện tại.
String toolLabel(BuildContext context, ToolSpec tool) =>
    toolLabelFor(context.l10n, tool.labelKey);

/// Như [toolLabel] nhưng nhận [AppLocalizations] (tiện cho test).
String toolLabelFor(AppLocalizations l, String labelKey) => switch (labelKey) {
  'core_toolImageToPdf' => l.core_toolImageToPdf,
  'core_toolScanner' => l.core_toolScanner,
  'core_toolTextToPdf' => l.core_toolTextToPdf,
  'core_toolCreateBlank' => l.core_toolCreateBlank,
  'core_toolWordToPdf' => l.core_toolWordToPdf,
  'core_toolExcelToPdf' => l.core_toolExcelToPdf,
  'core_toolCsvToPdf' => l.core_toolCsvToPdf,
  'core_toolPdfToImage' => l.core_toolPdfToImage,
  'core_toolPdfToText' => l.core_toolPdfToText,
  'core_toolPdfToWord' => l.core_toolPdfToWord,
  'core_toolPdfToExcel' => l.core_toolPdfToExcel,
  'core_toolPdfToCsv' => l.core_toolPdfToCsv,
  'core_toolMerge' => l.core_toolMerge,
  'core_toolSplit' => l.core_toolSplit,
  'core_toolOrganize' => l.core_toolOrganize,
  'core_toolLock' => l.core_toolLock,
  'core_toolUnlock' => l.core_toolUnlock,
  'core_toolWatermark' => l.core_toolWatermark,
  'core_toolAnnotate' => l.core_toolAnnotate,
  'core_toolSign' => l.core_toolSign,
  'core_toolFillForm' => l.core_toolFillForm,
  'core_toolIdCard' => l.core_toolIdCard,
  'core_toolQrScan' => l.core_toolQrScan,
  'core_toolPptToPdf' => l.core_toolPptToPdf,
  'core_toolPdfToPpt' => l.core_toolPdfToPpt,
  'core_toolCompress' => l.core_toolCompress,
  'core_toolPageNumbers' => l.core_toolPageNumbers,
  'core_toolInsertPages' => l.core_toolInsertPages,
  _ => labelKey,
};
