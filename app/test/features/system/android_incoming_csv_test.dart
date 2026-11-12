import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_office/core/utils/doc_type.dart';

/// Cấu hình phía Android phải khai báo đủ đuôi app mở được. Thiếu một chỗ là file
/// (vd. `.csv`) không hiện trong "Mở bằng" hoặc bị kênh native chặn — lỗi 12/11/2026.
///
/// Test đọc file nguồn, không chạy app: mục đích là bắt lệch giữa
/// `documentExtensions` (Dart) với intent-filter (manifest) và allowlist (Kotlin).
void main() {
  final manifest = _sourceFile('android/app/src/main/AndroidManifest.xml');
  final channelFile = _sourceFile(
    'android/app/src/main/kotlin/com/phuong/pdfoffice/IncomingFilesChannel.kt',
  );

  /// Các mime dùng cho `.csv` — nhiều app gửi một trong số này.
  const csvMimes = [
    'text/csv',
    'text/comma-separated-values',
    'application/csv',
  ];

  test('manifest: "Mở bằng" (ACTION_VIEW) nhận mime CSV', () {
    final filter = _intentFilter(manifest.readAsStringSync(), 'VIEW');
    for (final mime in csvMimes) {
      expect(
        filter,
        contains('android:mimeType="$mime"'),
        reason: 'thiếu $mime trong intent-filter ACTION_VIEW',
      );
    }
  });

  test('manifest: "Chia sẻ" (ACTION_SEND) nhận mime CSV', () {
    final filter = _intentFilter(manifest.readAsStringSync(), 'SEND');
    for (final mime in csvMimes) {
      expect(
        filter,
        contains('android:mimeType="$mime"'),
        reason: 'thiếu $mime trong intent-filter ACTION_SEND',
      );
    }
  });

  test('kênh native cho phép mọi đuôi trong documentExtensions', () {
    final kt = channelFile.readAsStringSync();
    final allowed = _setOf(kt, 'ALLOWED_EXTENSIONS');
    expect(allowed, isNotEmpty, reason: 'không đọc được ALLOWED_EXTENSIONS');
    expect(
      allowed,
      containsAll(documentExtensions),
      reason:
          'IncomingFilesChannel.ALLOWED_EXTENSIONS thiếu đuôi so với '
          'documentExtensions',
    );
  });

  test('kênh native đổi được mime CSV thành đuôi csv', () {
    final kt = channelFile.readAsStringSync();
    final mimes = _mapOf(kt, 'MIME_EXTENSIONS');
    expect(mimes, isNotEmpty, reason: 'không đọc được MIME_EXTENSIONS');
    expect(
      mimes.entries.where((e) => e.value == 'csv').map((e) => e.key),
      containsAll(csvMimes),
    );
  });
}

/// File nguồn tìm từ thư mục chạy test đi ngược lên (chạy được từ `app/` hoặc gốc repo).
File _sourceFile(String relative) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final file = File('${dir.path}/$relative');
    if (file.existsSync()) return file;
    dir = dir.parent;
  }
  fail('không tìm thấy $relative từ ${Directory.current.path}');
}

/// Nội dung khối `<intent-filter>` chứa action cho trước.
String _intentFilter(String manifest, String action) {
  final filters = RegExp(r'<intent-filter>[\s\S]*?</intent-filter>')
      .allMatches(manifest)
      .map((m) => m[0]!);
  // Khớp cả dấu `"` cuối để SEND không bắt nhầm SEND_MULTIPLE.
  final needle = 'android:name="android.intent.action.$action"';
  final match = filters.where((f) => f.contains(needle));
  expect(match, hasLength(1), reason: 'phải có đúng một intent-filter $action');
  return match.single;
}

/// Các chuỗi trong `private val NAME = setOf(...)` (dạng camelCase → snake_case).
Set<String> _setOf(String source, String name) {
  final match = RegExp('$name\\s*=\\s*setOf\\(([\\s\\S]*?)\\)')
      .firstMatch(source);
  if (match == null) return {};
  return RegExp(r'"([^"]+)"').allMatches(match[1]!).map((m) => m[1]!).toSet();
}

/// Các cặp `"mime" to "ext"` trong `private val NAME = mapOf(...)`.
Map<String, String> _mapOf(String source, String name) {
  final match = RegExp('$name\\s*=\\s*mapOf\\(([\\s\\S]*?)\\n\\s*\\)')
      .firstMatch(source);
  if (match == null) return {};
  return {
    for (final m in RegExp(r'"([^"]+)"\s*to\s*"([^"]+)"').allMatches(match[1]!))
      m[1]!: m[2]!,
  };
}
