import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_office/core/errors/app_error.dart';
import 'package:pdf_office/core/utils/cancel_token.dart';
import 'package:pdf_office/features/convert/engine/font_set.dart';
import 'package:pdf_office/features/convert/engine/pdf_convert_engine.dart';
import 'package:pdf_office/features/office_viewer/data/csv_reader.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

const _csv =
    'Name,Rank,Score\r\n'
    'An,1,9.5\r\n'
    'Binh,2,8\r\n'
    'Chi,3,"7,5"\r\n';

const _fontDir = r'C:\Windows\Fonts\';
final _hasFonts = File('${_fontDir}arial.ttf').existsSync();
final _skipNoFonts = _hasFonts ? null : r'cần font ở C:\Windows\Fonts (chỉ có trên Windows)';

const _winFonts = FileFontSource({FontSlot.regular: '${_fontDir}arial.ttf', FontSlot.bold: '${_fontDir}arialbd.ttf'});

String _pdfText(String path) {
  final doc = sf.PdfDocument(inputBytes: File(path).readAsBytesSync());
  try {
    return sf.PdfTextExtractor(doc).extractText();
  } finally {
    doc.dispose();
  }
}

int _pdfPages(String path) {
  final doc = sf.PdfDocument(inputBytes: File(path).readAsBytesSync());
  try {
    return doc.pages.count;
  } finally {
    doc.dispose();
  }
}

/// Bỏ BOM rồi giải mã, để so nội dung như người dùng thấy.
String _csvText(String path) {
  final bytes = File(path).readAsBytesSync();
  final start = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0;
  return utf8.decode(bytes.sublist(start));
}

/// Toàn bộ ô của sheet đọc lại được từ CSV, dạng chuỗi.
List<String> _values(String csvPath) {
  final sheet = parseCsv(_csvText(csvPath)).workbook.sheets.single;
  final values = <String>[];
  for (var r = 0; r < sheet.maxRow; r++) {
    for (var c = 0; c < sheet.maxCol; c++) {
      final cell = sheet.cell(r, c);
      if (cell != null) values.add(cell.display);
    }
  }
  return values;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('csv_convert_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String out(String name) => p.join(tmp.path, name);

  const engine = PdfConvertEngine(fontSource: NoFontSource());

  group('CSV → PDF', () {
    test('bảng CSV thành bảng trong PDF, có chữ các ô', () async {
      final wb = parseCsv(_csv, sheetName: 'Scores').workbook;
      final path = await engine.tableToPdf(wb, out('scores.pdf'));
      expect(File(path).existsSync(), isTrue);
      expect(_pdfPages(path), greaterThanOrEqualTo(1));
      final t = _pdfText(path);
      for (final s in ['Name', 'Rank', 'Score', 'An', '9.5', 'Binh', 'Chi']) {
        expect(t, contains(s));
      }
    });

    test('tableToPdf huỷ trước khi chạy → Cancelled, không để file', () async {
      final wb = parseCsv(_csv).workbook;
      final token = CancelToken()..cancel();
      await expectLater(engine.tableToPdf(wb, out('huy.pdf'), cancelToken: token), throwsA(isA<Cancelled>()));
      expect(File(out('huy.pdf')).existsSync(), isFalse);
    });

    test('tiếng Việt có dấu giữ nguyên trong PDF', skip: _skipNoFonts, () async {
      const vi = 'Tên,Hạng,Điểm\r\nAn,1,9.5\r\nBình,2,8\r\n';
      const viEngine = PdfConvertEngine(fontSource: _winFonts);
      final pdf = await viEngine.tableToPdf(parseCsv(vi, sheetName: 'Bảng điểm').workbook, out('vi.pdf'));
      final t = _pdfText(pdf);
      for (final s in ['Tên', 'Điểm', 'Bình']) {
        expect(t, contains(s));
      }
    });
  });

  group('PDF → CSV', () {
    test('bảng trong PDF thành CSV: BOM, CRLF, đúng giá trị ô', () async {
      final wb = parseCsv(_csv, sheetName: 'Scores').workbook;
      final pdf = await engine.tableToPdf(wb, out('in.pdf'));

      final path = await engine.pdfToCsv(pdf, out('ra.csv'));
      final bytes = File(path).readAsBytesSync();
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(_csvText(path), contains('\r\n'));

      final text = _csvText(path);
      for (final s in ['Name', 'Rank', 'Score', 'An', 'Binh', 'Chi']) {
        expect(text, contains(s));
      }
      expect(_values(path).any((v) => v.contains('7,5')), isTrue);
    });

    test('CSV → PDF → CSV giữ được các ô chính', () async {
      final wb = parseCsv(_csv, sheetName: 'Scores').workbook;
      final pdf = await engine.tableToPdf(wb, out('rt.pdf'));
      final back = await engine.pdfToCsv(pdf, out('rt.csv'));

      final values = _values(back);
      for (final s in ['Name', 'Rank', 'Score', 'An', '9.5', 'Binh', 'Chi']) {
        expect(values.any((v) => v.contains(s)), isTrue, reason: s);
      }
      expect(values.any((v) => v.contains('7,5')), isTrue);
    });

    test('PDF không có chữ → NoTextFound', () async {
      final doc = sf.PdfDocument()..pages.add();
      File(out('blank.pdf')).writeAsBytesSync(doc.saveSync());
      doc.dispose();
      await expectLater(engine.pdfToCsv(out('blank.pdf'), out('b.csv')), throwsA(predicate(isNoTextError)));
      expect(File(out('b.csv')).existsSync(), isFalse);
    });
  });

  test('CSV đọc từ file (UTF-8) → PDF: đúng số dòng', () async {
    File(out('in.csv')).writeAsBytesSync(utf8.encode(_csv));
    final content = readCsvFileSync(out('in.csv'));
    expect(content.truncated, isFalse);
    final pdf = await engine.tableToPdf(content.workbook, out('u.pdf'));
    final t = _pdfText(pdf);
    for (final s in ['Name', 'An', 'Binh', 'Chi']) {
      expect(t, contains(s));
    }
  });
}
