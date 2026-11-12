import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_office/core/utils/doc_type.dart';

void main() {
  group('docTypeFromPath', () {
    test('nhận đuôi không phân biệt hoa thường', () {
      expect(docTypeFromPath('/a/b/Report.PDF'), DocType.pdf);
      expect(docTypeFromPath('x.docx'), DocType.docx);
      expect(docTypeFromPath('x.doc'), DocType.doc);
      expect(docTypeFromPath('x.XLSX'), DocType.xlsx);
      expect(docTypeFromPath('x.xls'), DocType.xls);
      expect(docTypeFromPath('x.CSV'), DocType.csv);
      expect(docTypeFromPath('x.pptx'), DocType.pptx);
      expect(docTypeFromPath('x.ppt'), DocType.ppt);
      expect(docTypeFromPath('notes.txt'), DocType.txt);
    });

    test('ảnh và loại khác', () {
      for (final e in ['jpg', 'jpeg', 'png', 'webp', 'heic']) {
        expect(docTypeFromPath('a.$e'), DocType.image, reason: e);
      }
      expect(docTypeFromPath('a.zip'), DocType.other);
      expect(docTypeFromPath('noext'), DocType.other);
      expect(docTypeFromPath('/dir.pdf/file'), DocType.other);
    });

    test('extensionOf', () {
      expect(extensionOf('/a/b.tar.GZ'), 'gz');
      expect(extensionOf('abc'), '');
    });
  });

  group('DocTypeX', () {
    test('category gom đuôi cũ và mới', () {
      expect(DocType.pdf.category, DocCategory.pdf);
      expect(DocType.doc.category, DocCategory.doc);
      expect(DocType.docx.category, DocCategory.doc);
      expect(DocType.xls.category, DocCategory.xls);
      expect(DocType.xlsx.category, DocCategory.xls);
      expect(DocType.csv.category, DocCategory.xls);
      expect(DocType.ppt.category, DocCategory.ppt);
      expect(DocType.pptx.category, DocCategory.ppt);
      expect(DocType.txt.category, DocCategory.txt);
      expect(DocType.image.category, isNull);
      expect(DocType.other.category, isNull);
    });

    test('isLegacyOffice chỉ doc/xls/ppt', () {
      expect(DocType.values.where((t) => t.isLegacyOffice).toSet(), {
        DocType.doc,
        DocType.xls,
        DocType.ppt,
      });
    });

    test('label', () {
      expect(DocType.pdf.label, 'PDF');
      expect(DocType.docx.label, 'DOC');
      expect(DocType.xlsx.label, 'XLS');
      expect(DocType.csv.label, 'CSV');
    });

    test('csv nằm trong danh sách đuôi quét', () {
      expect(documentExtensions, contains('csv'));
    });
  });
}
