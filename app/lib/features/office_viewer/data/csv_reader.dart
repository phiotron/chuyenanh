import 'dart:io';
import 'dart:math' as math;

import 'package:office_reader/office_reader.dart' as rd;
import 'package:path/path.dart' as p;

import 'text_decoder.dart' show decodeText;

/// File CSV lớn hơn mức này chỉ đọc phần đầu (byte) — cùng ngưỡng với file TXT.
const int maxCsvBytes = 20 * 1024 * 1024;

/// Số ô tối đa giữ lại để không nặng RAM trên máy yếu.
const int maxCsvCells = 500000;

const int _quote = 0x22; // "
const int _cr = 0x0D;
const int _lf = 0x0A;
const int _comma = 0x2C;
const List<int> _delimiters = [_comma, 0x3B, 0x09, 0x7C]; // , ; tab |

final RegExp _numeric = RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$');

/// Bảng đọc được từ `.xlsx` hoặc `.csv`, kèm cờ báo dữ liệu bị cắt bớt.
class SpreadsheetContent {
  const SpreadsheetContent(this.workbook, {this.truncated = false});

  final rd.XlsxWorkbook workbook;

  /// File quá lớn / quá nhiều ô nên chỉ hiển thị phần đầu.
  final bool truncated;
}

/// Kết quả đọc một chuỗi CSV.
class CsvParseResult {
  const CsvParseResult(this.workbook, {this.truncated = false});

  final rd.XlsxWorkbook workbook;
  final bool truncated;
}

/// Đọc `.csv` thành bảng một sheet (tên sheet = tên file). Đồng bộ — gọi trong isolate.
///
/// Nhận mã UTF-8 / UTF-8 BOM / UTF-16 / Windows-1252 như trình xem TXT.
SpreadsheetContent readCsvFileSync(String path) {
  final raf = File(path).openSync();
  try {
    final length = raf.lengthSync();
    final tooLarge = length > maxCsvBytes;
    final bytes = raf.readSync(tooLarge ? maxCsvBytes : length);
    final text = decodeText(bytes, truncated: tooLarge).text;
    final parsed = parseCsv(text, sheetName: p.basenameWithoutExtension(path));
    return SpreadsheetContent(
      parsed.workbook,
      truncated: tooLarge || parsed.truncated,
    );
  } finally {
    raf.closeSync();
  }
}

/// Tách [text] thành bảng theo chuẩn CSV: ô có ngoặc kép, `""` = một dấu `"`,
/// xuống dòng bên trong ô, CRLF. Tự nhận dấu phân cách `,` `;` tab `|`.
///
/// Ô rỗng bị bỏ qua (lưới vẫn giữ đúng toạ độ). Chuỗi giống số được căn phải.
CsvParseResult parseCsv(String text, {String sheetName = 'CSV'}) {
  final delimiter = _detectDelimiter(text);
  final parsed = _parseRows(text, delimiter, maxCells: maxCsvCells);
  final rows = parsed.rows;

  // Bỏ các hàng trống ở cuối (file thường kết thúc bằng một dòng trắng).
  while (rows.isNotEmpty && rows.last.every((cell) => cell.isEmpty)) {
    rows.removeLast();
  }

  var maxCol = 0;
  for (final row in rows) {
    maxCol = math.max(maxCol, row.length);
  }

  final maxChars = List<int>.filled(maxCol, 0);
  final cells = <(int, int), rd.XlsxCell>{};
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    for (var c = 0; c < row.length; c++) {
      final s = row[c];
      if (s.isEmpty) continue;
      final value = _numeric.hasMatch(s) ? double.tryParse(s) : null;
      cells[(r, c)] = rd.XlsxCell(
        display: s,
        raw: value ?? s,
        type: value == null ? rd.XlsxCellType.string : rd.XlsxCellType.number,
        style: rd.XlsxStyle.plain,
      );
      if (s.length > maxChars[c]) maxChars[c] = s.length;
    }
  }

  final sheet = rd.XlsxSheet(
    name: sheetName.trim().isEmpty ? 'CSV' : sheetName.trim(),
    maxRow: rows.length,
    maxCol: maxCol,
    cells: cells,
    columnWidthsChars: {
      for (var c = 0; c < maxCol; c++)
        c: (maxChars[c] + 2).clamp(6, 40).toDouble(),
    },
  );
  return CsvParseResult(
    rd.XlsxWorkbook(sheets: [sheet]),
    truncated: parsed.truncated,
  );
}

/// Chọn dấu phân cách có số cột ổn định nhất trong vài dòng đầu.
int _detectDelimiter(String text) {
  var best = _comma;
  var bestScore = 0;
  for (final delimiter in _delimiters) {
    final preview = _parseRows(text, delimiter, maxRows: 5, maxCells: 20000);
    final counts = <int, int>{};
    for (final row in preview.rows) {
      if (row.length > 1) {
        counts[row.length] = (counts[row.length] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) continue;
    var modeCount = 0;
    var modeCols = 0;
    counts.forEach((cols, n) {
      if (n > modeCount || (n == modeCount && cols > modeCols)) {
        modeCount = n;
        modeCols = cols;
      }
    });
    final score = modeCount * 1000 + modeCols;
    if (score > bestScore) {
      bestScore = score;
      best = delimiter;
    }
  }
  return best;
}

class _ParsedRows {
  const _ParsedRows(this.rows, this.truncated);

  final List<List<String>> rows;
  final bool truncated;
}

/// Máy trạng thái CSV. [maxRows] > 0 = chỉ đọc vài dòng đầu để dò dấu phân cách
/// (không đánh dấu cắt dữ liệu).
_ParsedRows _parseRows(
  String text,
  int delimiter, {
  int maxRows = 0,
  int maxCells = 0,
}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var atFieldStart = true;
  var cells = 0;
  var truncated = false;
  var stop = false;

  void finishField() {
    row.add(field.toString());
    field.clear();
    atFieldStart = true;
    cells++;
  }

  for (var i = 0; i < text.length && !stop; i++) {
    final ch = text.codeUnitAt(i);
    if (inQuotes) {
      if (ch == _quote) {
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == _quote) {
          field.writeCharCode(_quote);
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.writeCharCode(ch);
      }
      continue;
    }
    if (ch == _quote && atFieldStart) {
      inQuotes = true;
      atFieldStart = false;
      continue;
    }
    if (ch == delimiter) {
      finishField();
      if (maxCells > 0 && cells >= maxCells) {
        truncated = true;
        stop = true;
      }
      continue;
    }
    if (ch == _cr || ch == _lf) {
      finishField();
      rows.add(row);
      row = <String>[];
      if (ch == _cr && i + 1 < text.length && text.codeUnitAt(i + 1) == _lf) {
        i++;
      }
      if (maxCells > 0 && cells >= maxCells) {
        truncated = true;
        stop = true;
      } else if (maxRows > 0 && rows.length >= maxRows) {
        stop = true;
      }
      continue;
    }
    field.writeCharCode(ch);
    atFieldStart = false;
  }

  // Không kết thúc bằng dấu phân cách / xuống dòng → còn một ô cuối.
  if (!truncated && (field.isNotEmpty || row.isNotEmpty)) {
    finishField();
    rows.add(row);
  }
  return _ParsedRows(rows, truncated);
}
