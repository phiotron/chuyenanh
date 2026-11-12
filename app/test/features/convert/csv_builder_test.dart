import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_layout/pdf_layout.dart';
import 'package:pdf_office/features/convert/engine/csv_builder.dart';

void main() {
  group('csvField', () {
    test('ô thường giữ nguyên', () {
      expect(csvField('Apple'), 'Apple');
      expect(csvField('12'), '12');
      expect(csvField(''), '');
      expect(csvField('tiếng Việt có dấu'), 'tiếng Việt có dấu');
    });

    test('có dấu phẩy / ngoặc kép / xuống dòng → bọc ngoặc kép', () {
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('say "hi"'), '"say ""hi"""');
      expect(csvField('dòng 1\ndòng 2'), '"dòng 1\ndòng 2"');
      expect(csvField('a\r\nb'), '"a\r\nb"');
    });
  });

  group('csvFromSheets', () {
    test('mỗi dòng một khối, CRLF, ngăn các bảng bằng một dòng trống', () {
      final text = csvFromSheets(const [
        SheetGrid(
          name: 'Page 1',
          rows: [
            ['Item', 'Price'],
            ['Apple', '12'],
          ],
        ),
        SheetGrid(
          name: 'Page 2',
          rows: [
            ['Other', 'a,b'],
          ],
        ),
      ]);
      expect(text, 'Item,Price\r\nApple,12\r\n\r\nOther,"a,b"\r\n');
    });

    test('không có bảng → chuỗi rỗng', () {
      expect(csvFromSheets(const []), '');
      expect(csvFromSheets(const [SheetGrid(name: 'Page 1', rows: [])]), '');
    });

    test('hàng lệch cột giữ đúng số ô của hàng đó', () {
      expect(
        csvFromSheets(const [
          SheetGrid(
            name: 'Page 1',
            rows: [
              ['a', 'b', 'c'],
              ['x'],
            ],
          ),
        ]),
        'a,b,c\r\nx\r\n',
      );
    });
  });

  group('csvBytes', () {
    test('có BOM UTF-8 và nội dung tiếng Việt', () {
      final bytes = csvBytes('Tên,Điểm\r\nAn,9\r\n');
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.sublist(3)), 'Tên,Điểm\r\nAn,9\r\n');
    });
  });
}
