import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_office/core/navigation/open_document.dart';
import 'package:pdf_office/core/router/routes.dart';

void main() {
  test('routeForDocument theo loại', () {
    expect(routeForDocument('/a/x.pdf'), Routes.pdfReader);
    expect(routeForDocument('/a/x.DOCX'), Routes.docxViewer);
    expect(routeForDocument('/a/x.xlsx'), Routes.xlsxViewer);
    expect(routeForDocument('/a/x.CSV'), Routes.xlsxViewer);
    expect(routeForDocument('/a/x.pptx'), Routes.pptxViewer);
    expect(routeForDocument('/a/x.txt'), Routes.txtViewer);
    expect(routeForDocument('/a/x.doc'), isNull);
    expect(routeForDocument('/a/x.xls'), isNull);
    expect(routeForDocument('/a/x.ppt'), isNull);
    expect(routeForDocument('/a/x.zip'), isNull);
  });

  test('OpenFileArgs so sánh theo giá trị', () {
    expect(
      const OpenFileArgs('a', initialPage: 2),
      const OpenFileArgs('a', initialPage: 2),
    );
    expect(const OpenFileArgs('a') == const OpenFileArgs('b'), isFalse);
  });
}
