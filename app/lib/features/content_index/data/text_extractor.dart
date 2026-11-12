// Trích chữ thuần từ tài liệu để lập chỉ mục. Không OCR (trang ảnh / bản quét → không có chữ).
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:office_reader/office_reader.dart' as office;
import 'package:pptx_reader/pptx_reader.dart' as pptx;

import '../../convert/engine/pdf_builders.dart'
    show docxPlainText, xlsxPlainText;
import '../../convert/engine/pdf_extract.dart'
    show extractLayoutPages, layoutPagesToText;
import '../../office_viewer/data/text_decoder.dart' show decodeText;
import '../logic/search_text.dart';

/// File lớn hơn mức này không lập chỉ mục (đọc cả file vào RAM quá nặng cho máy yếu).
const int maxIndexedFileBytes = 50 * 1024 * 1024;

/// Đuôi file trích được chữ. `.doc/.xls/.ppt` đời cũ không đọc được → bỏ.
const Set<String> indexableExtensions = {
  'pdf',
  'docx',
  'xlsx',
  'csv',
  'pptx',
  'txt',
};

/// TXT: chỉ đọc phần đầu, đủ cho [maxContentChars] ký tự kể cả mã 2–4 byte/ký tự.
const int _maxTxtBytes = 4 * maxContentChars;

/// Chữ thuần của file [path] (đuôi [ext], chữ thường). Đồng bộ — gọi trong isolate.
/// Ném lỗi khi file hỏng / PDF có mật khẩu (`PasswordRequired`).
String extractRawText(String path, String ext) {
  switch (ext) {
    case 'pdf':
      return layoutPagesToText(
        extractLayoutPages(File(path).readAsBytesSync()),
      );
    case 'docx':
      return docxPlainText(office.readDocx(File(path).readAsBytesSync()));
    case 'xlsx':
      return xlsxPlainText(office.readXlsx(File(path).readAsBytesSync()));
    case 'pptx':
      return pptxPlainText(pptx.readPptx(File(path).readAsBytesSync()));
    case 'txt' || 'csv':
      final raf = File(path).openSync();
      try {
        final length = raf.lengthSync();
        final truncated = length > _maxTxtBytes;
        final Uint8List bytes = raf.readSync(truncated ? _maxTxtBytes : length);
        return decodeText(bytes, truncated: truncated).text;
      } finally {
        raf.closeSync();
      }
    default:
      return '';
  }
}

/// Chữ của mọi slide: hộp chữ, bảng, nhóm (đệ quy) + ghi chú người trình bày.
String pptxPlainText(pptx.PptxDeck deck) {
  final b = StringBuffer();
  void paragraphs(List<pptx.PptxParagraph> ps) {
    for (final p in ps) {
      b.writeln(p.runs.map((r) => r.isLineBreak ? '\n' : r.text).join());
    }
  }

  void shapes(List<pptx.PptxShape> list) {
    for (final s in list) {
      if (s is pptx.PptxTextShape) {
        paragraphs(s.paragraphs);
      } else if (s is pptx.PptxTableShape) {
        for (final row in s.rows) {
          for (final cell in row.cells) {
            paragraphs(cell.paragraphs);
          }
        }
      } else if (s is pptx.PptxGroupShape) {
        shapes(s.children);
      }
    }
  }

  for (final slide in deck.slides) {
    shapes(slide.shapes);
    final notes = slide.notesText;
    if (notes != null && notes.isNotEmpty) b.writeln(notes);
  }
  return b.toString();
}

/// Trích + chuẩn bị chữ (đồng bộ, trong isolate): trả cả `content` lẫn `normalized` để
/// isolate giao diện không phải xử lý chuỗi dài.
PreparedText extractPreparedText(String path, String ext) =>
    prepareContent(extractRawText(path, ext));

/// Trích chữ trong isolate riêng. `null` = không lấy được chữ (PDF có mật khẩu, file hỏng /
/// không đọc được); bên gọi lưu dòng rỗng để không thử lại tới khi file đổi.
Future<PreparedText?> extractTextInIsolate(String path, String ext) async {
  try {
    return await Isolate.run(() => extractPreparedText(path, ext));
  } catch (_) {
    return null;
  }
}
