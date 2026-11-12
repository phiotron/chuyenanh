import 'package:path/path.dart' as p;

/// Loại file theo đuôi (không phân biệt hoa thường).
enum DocType { pdf, doc, docx, xls, xlsx, csv, ppt, pptx, txt, image, other }

/// Nhóm file cho tab trang chủ: All · PDF · DOC · XLS · PPT · TXT.
enum DocCategory { pdf, doc, xls, ppt, txt }

const Set<String> imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  'bmp',
  'gif',
};

/// Đuôi file (chữ thường, không có dấu chấm). `'a/b.PDF'` → `'pdf'`, không đuôi → `''`.
String extensionOf(String path) {
  final ext = p.extension(path);
  return ext.isEmpty ? '' : ext.substring(1).toLowerCase();
}

DocType docTypeFromPath(String path) => docTypeFromExtension(extensionOf(path));

DocType docTypeFromExtension(String ext) {
  final e = ext.toLowerCase().replaceFirst('.', '');
  switch (e) {
    case 'pdf':
      return DocType.pdf;
    case 'doc':
      return DocType.doc;
    case 'docx':
      return DocType.docx;
    case 'xls':
      return DocType.xls;
    case 'xlsx':
      return DocType.xlsx;
    case 'csv':
      return DocType.csv;
    case 'ppt':
      return DocType.ppt;
    case 'pptx':
      return DocType.pptx;
    case 'txt':
      return DocType.txt;
  }
  if (imageExtensions.contains(e)) return DocType.image;
  return DocType.other;
}

extension DocTypeX on DocType {
  /// Nhóm tab của loại file; `null` với ảnh / khác.
  DocCategory? get category => switch (this) {
    DocType.pdf => DocCategory.pdf,
    DocType.doc || DocType.docx => DocCategory.doc,
    DocType.xls || DocType.xlsx || DocType.csv => DocCategory.xls,
    DocType.ppt || DocType.pptx => DocCategory.ppt,
    DocType.txt => DocCategory.txt,
    DocType.image || DocType.other => null,
  };

  /// Đuôi đời cũ (.doc/.xls/.ppt) — mở bằng app ngoài.
  bool get isLegacyOffice =>
      this == DocType.doc || this == DocType.xls || this == DocType.ppt;

  /// Nhãn ngắn vẽ trên biểu tượng file.
  String get label => switch (this) {
    DocType.pdf => 'PDF',
    DocType.doc || DocType.docx => 'DOC',
    DocType.xls || DocType.xlsx => 'XLS',
    DocType.csv => 'CSV',
    DocType.ppt || DocType.pptx => 'PPT',
    DocType.txt => 'TXT',
    DocType.image => 'IMG',
    DocType.other => 'FILE',
  };
}

/// Mọi đuôi mà app quét / liệt kê ở trang chủ.
const Set<String> documentExtensions = {
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'csv',
  'ppt',
  'pptx',
  'txt',
};
