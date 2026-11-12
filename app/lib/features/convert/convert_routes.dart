import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'convert_screen.dart';

GoRoute _route(String path, ConvertMode mode) => GoRoute(
      path: path,
      builder: (context, state) =>
          ConvertScreen(mode: mode, initialPath: state.extra as String?),
    );

/// Route của feature `convert` (gộp trong `core/router/app_router.dart`).
final List<RouteBase> convertRoutes = [
  _route(Routes.textToPdf, ConvertMode.textToPdf),
  _route(Routes.wordToPdf, ConvertMode.wordToPdf),
  _route(Routes.excelToPdf, ConvertMode.excelToPdf),
  _route(Routes.csvToPdf, ConvertMode.csvToPdf),
  _route(Routes.pdfToText, ConvertMode.pdfToText),
  _route(Routes.pdfToWord, ConvertMode.pdfToWord),
  _route(Routes.pdfToExcel, ConvertMode.pdfToExcel),
  _route(Routes.pdfToCsv, ConvertMode.pdfToCsv),
];
