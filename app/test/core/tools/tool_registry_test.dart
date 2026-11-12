import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_office/core/l10n/l10n.dart';
import 'package:pdf_office/core/router/routes.dart';
import 'package:pdf_office/core/tools/tool_registry.dart';

void main() {
  test('id và route không trùng', () {
    expect(allTools.map((t) => t.id).toSet().length, allTools.length);
    expect(allTools.map((t) => t.route).toSet().length, allTools.length);
  });

  test('đủ công cụ của spec', () {
    final routes = allTools.map((t) => t.route).toSet();
    expect(
      routes,
      containsAll([
        Routes.imageToPdf,
        Routes.scanner,
        Routes.textToPdf,
        Routes.createBlank,
        Routes.wordToPdf,
        Routes.excelToPdf,
        Routes.csvToPdf,
        Routes.pdfToImage,
        Routes.pdfToText,
        Routes.pdfToWord,
        Routes.pdfToExcel,
        Routes.pdfToCsv,
        Routes.merge,
        Routes.split,
        Routes.organize,
        Routes.lock,
        Routes.unlock,
        Routes.watermark,
        Routes.annotate,
        Routes.sign,
        Routes.fillForm,
      ]),
    );
  });

  test('công cụ chỉnh sửa bắt buộc chọn PDF trước', () {
    for (final id in ['annotate', 'sign', 'fillForm']) {
      expect(toolById(id)!.inputType, ToolInputType.pdfRequired);
    }
    expect(toolById('nope'), isNull);
  });

  test('mọi labelKey có chuỗi ở 2 ngôn ngữ (vi, en)', () async {
    expect(AppLocalizations.supportedLocales.length, 2);
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      for (final t in allTools) {
        final label = toolLabelFor(l, t.labelKey);
        expect(label, isNot(t.labelKey), reason: '${t.labelKey} @ $locale');
        expect(label, isNotEmpty);
      }
    }
  });
}
