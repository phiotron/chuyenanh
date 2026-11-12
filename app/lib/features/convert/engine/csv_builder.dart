import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_layout/pdf_layout.dart';

/// Ghi CSV theo RFC 4180: bọc ngoặc kép khi ô có `,` `"` hoặc xuống dòng, `"` → `""`.
String csvField(String value) {
  final needsQuote =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuote) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Các bảng đoán được từ PDF → nội dung CSV: mỗi bảng một khối dòng, cách nhau một
/// dòng trống. Xuống dòng kiểu Windows (CRLF) như Excel xuất ra.
String csvFromSheets(List<SheetGrid> grids) {
  final buffer = StringBuffer();
  for (var i = 0; i < grids.length; i++) {
    if (i > 0) buffer.write('\r\n');
    for (final row in grids[i].rows) {
      buffer
        ..write(row.map(csvField).join(','))
        ..write('\r\n');
    }
  }
  return buffer.toString();
}

/// Nội dung CSV → byte UTF-8 **có BOM**: Excel trên Windows mở đúng tiếng Việt.
Uint8List csvBytes(String text) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
