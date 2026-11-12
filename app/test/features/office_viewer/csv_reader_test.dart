import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:office_reader/office_reader.dart' as rd;
import 'package:pdf_office/features/office_viewer/data/csv_reader.dart';

void main() {
  group('parseCsv', () {
    test('dấu phẩy: giữ đúng số hàng/cột', () {
      final r = parseCsv('name,age\nAn,20\nBinh,30\n');
      final sheet = r.workbook.sheets.single;
      expect(sheet.maxRow, 3);
      expect(sheet.maxCol, 2);
      expect(sheet.cell(0, 0)!.display, 'name');
      expect(sheet.cell(2, 1)!.display, '30');
      expect(r.truncated, isFalse);
    });

    test('ô có ngoặc kép: dấu phân cách và "" bên trong', () {
      final sheet = parseCsv('"a,b","say ""hi"""\n').workbook.sheets.single;
      expect(sheet.maxCol, 2);
      expect(sheet.cell(0, 0)!.display, 'a,b');
      expect(sheet.cell(0, 1)!.display, 'say "hi"');
    });

    test('xuống dòng bên trong ô ngoặc kép', () {
      final sheet = parseCsv('"dòng 1\ndòng 2",x\n').workbook.sheets.single;
      expect(sheet.maxRow, 1);
      expect(sheet.cell(0, 0)!.display, 'dòng 1\ndòng 2');
      expect(sheet.cell(0, 1)!.display, 'x');
    });

    test('CRLF không tạo hàng trống', () {
      final sheet = parseCsv('a,b\r\nc,d\r\n').workbook.sheets.single;
      expect(sheet.maxRow, 2);
      expect(sheet.cell(1, 1)!.display, 'd');
    });

    test('tự nhận dấu chấm phẩy (số thập phân dùng dấu phẩy)', () {
      final sheet = parseCsv('ten;diem\nAn;1,5\nBinh;2,5\n')
          .workbook
          .sheets
          .single;
      expect(sheet.maxCol, 2);
      expect(sheet.cell(1, 1)!.display, '1,5');
    });

    test('tự nhận tab', () {
      final sheet = parseCsv('a\tb\tc\n1\t2\t3\n').workbook.sheets.single;
      expect(sheet.maxCol, 3);
      expect(sheet.cell(1, 2)!.display, '3');
    });

    test('ô số căn phải nhưng giữ nguyên chữ hiển thị', () {
      final sheet = parseCsv('001,2.5\n').workbook.sheets.single;
      expect(sheet.cell(0, 0)!.type, rd.XlsxCellType.number);
      expect(sheet.cell(0, 0)!.display, '001');
      expect(sheet.cell(0, 1)!.type, rd.XlsxCellType.number);
    });

    test('file rỗng → bảng rỗng', () {
      final sheet = parseCsv('').workbook.sheets.single;
      expect(sheet.maxRow, 0);
      expect(sheet.maxCol, 0);
      expect(sheet.cells, isEmpty);
    });

    test('độ rộng cột theo nội dung, tối thiểu 6 ký tự', () {
      final sheet = parseCsv('a,abcdefghij\n').workbook.sheets.single;
      expect(sheet.columnWidthsChars[0], 6);
      expect(sheet.columnWidthsChars[1], 12);
    });
  });

  group('readCsvFileSync', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('csv_reader_test');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('đọc UTF-8 BOM và lấy tên file làm tên sheet', () async {
      final file = File('${dir.path}/Bảng điểm.csv');
      await file.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('Tên,Điểm\nAn,9\n'),
      ]);
      final r = readCsvFileSync(file.path);
      final sheet = r.workbook.sheets.single;
      expect(sheet.name, 'Bảng điểm');
      expect(sheet.cell(0, 0)!.display, 'Tên');
      expect(sheet.cell(1, 1)!.display, '9');
      expect(r.truncated, isFalse);
    });

    test('đọc Windows-1252 (file ANSI cũ)', () async {
      final file = File('${dir.path}/old.csv');
      // "Tên" mã hoá Windows-1252: T = 0x54, ê = 0xEA, n = 0x6E.
      await file.writeAsBytes([0x54, 0xEA, 0x6E, 0x2C, 0x31]);
      final cell = readCsvFileSync(file.path).workbook.sheets.single.cell(0, 0);
      expect(cell!.display, 'Tên');
    });
  });
}
