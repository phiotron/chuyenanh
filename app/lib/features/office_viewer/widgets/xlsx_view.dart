import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:office_reader/office_reader.dart' as rd;
import 'package:path/path.dart' as p;
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/doc_type.dart';
import '../../../core/widgets/empty_state.dart';
import '../logic/xlsx_grid_layout.dart';
import '../logic/xlsx_search.dart';
import 'office_common.dart';

const double _headerColWidth = 44;
const double _headerRowHeight = 24;
const Color _hitMatch = Color(0xFFFFF59D);
const Color _hitCurrent = Color(0xFFFFB300);

/// Mức tô sáng của ô khi tìm kiếm.
enum XlsxHighlight { none, match, current }

const Color _gridLine = Color(0xFFD4D4D4);
const Color _headerBg = Color(0xFFEFEFEF);

class XlsxViewerPage extends StatefulWidget {
  const XlsxViewerPage({
    super.key,
    required this.path,
    required this.workbook,
    this.truncated = false,
  });

  final String path;
  final rd.XlsxWorkbook workbook;

  /// File quá lớn nên chỉ đọc phần đầu (CSV).
  final bool truncated;

  @override
  State<XlsxViewerPage> createState() => _XlsxViewerPageState();
}

class _XlsxViewerPageState extends State<XlsxViewerPage> {
  late final List<rd.XlsxSheet> _sheets = () {
    final visible = widget.workbook.sheets.where((s) => !s.hidden).toList();
    return visible.isEmpty ? widget.workbook.sheets : visible;
  }();
  int _index = 0;
  double _zoom = 1;

  /// CSV có tab + màu riêng (vàng); XLSX giữ màu xanh.
  late final DocCategory _category =
      docTypeFromPath(widget.path).category ?? DocCategory.xls;

  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<XlsxHit> _hits = const [];
  Set<(int, int)> _matchSet = const {};
  int _current = 0;
  final Map<int, XlsxGridLayout> _layouts = {};
  final Map<int, ScrollController> _hCtrls = {};
  final Map<int, ScrollController> _vCtrls = {};

  XlsxGridLayout _layoutOf(int i) =>
      _layouts.putIfAbsent(i, () => XlsxGridLayout(_sheets[i]));
  ScrollController _hOf(int i) =>
      _hCtrls.putIfAbsent(i, () => ScrollController());
  ScrollController _vOf(int i) =>
      _vCtrls.putIfAbsent(i, () => ScrollController());

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _hCtrls.values) {
      c.dispose();
    }
    for (final c in _vCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setZoom(double z) => setState(() => _zoom = z.clamp(0.5, 3.0));

  void _refreshMatchSet() {
    _matchSet = {
      for (final h in _hits)
        if (h.sheetIndex == _index) (h.row, h.col),
    };
  }

  void _onQuery(String q) {
    setState(() {
      _hits = findXlsxHits(_sheets, q);
      _current = 0;
      if (_hits.isNotEmpty) _index = _hits[0].sheetIndex;
      _refreshMatchSet();
    });
    _goToCurrent();
  }

  void _step(int delta) {
    if (_hits.isEmpty) return;
    setState(() {
      _current = (_current + delta + _hits.length) % _hits.length;
      _index = _hits[_current].sheetIndex;
      _refreshMatchSet();
    });
    _goToCurrent();
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _searchCtrl.clear();
    _hits = const [];
    _matchSet = const {};
    _current = 0;
  });

  /// Sau khung hình kế tiếp (lưới sheet mới đã gắn controller) cuộn cho ô
  /// hiện tại nằm trong vùng nhìn.
  void _goToCurrent() {
    if (_hits.isEmpty) return;
    final hit = _hits[_current];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final layout = _layoutOf(hit.sheetIndex);
      final h = _hOf(hit.sheetIndex), v = _vOf(hit.sheetIndex);
      if (h.hasClients && h.position.hasContentDimensions) {
        _reveal(
          h,
          start: _extent(layout.pinnedCols, hit.col, layout.columnWidth),
          size: layout.columnWidth(hit.col) * _zoom,
          pinned:
              _headerColWidth * _zoom +
              _extent(0, layout.pinnedCols, layout.columnWidth),
          pinnedCell: hit.col < layout.pinnedCols,
        );
      }
      if (v.hasClients && v.position.hasContentDimensions) {
        _reveal(
          v,
          start: _extent(layout.pinnedRows, hit.row, layout.rowHeight),
          size: layout.rowHeight(hit.row) * _zoom,
          pinned:
              _headerRowHeight * _zoom +
              _extent(0, layout.pinnedRows, layout.rowHeight),
          pinnedCell: hit.row < layout.pinnedRows,
        );
      }
    });
  }

  /// Tổng kích thước (đã nhân zoom) của các cột/hàng [from, to).
  double _extent(int from, int to, double Function(int) size) {
    var sum = 0.0;
    for (var i = from; i < to; i++) {
      sum += size(i);
    }
    return sum * _zoom;
  }

  void _reveal(
    ScrollController ctrl, {
    required double start,
    required double size,
    required double pinned,
    required bool pinnedCell,
  }) {
    if (pinnedCell) return;
    final pos = ctrl.position;
    final visible = pos.viewportDimension - pinned;
    var target = pos.pixels;
    if (start < target) {
      target = start;
    } else if (start + size > target + visible) {
      target = start + size - visible;
      if (size > visible) target = start;
    } else {
      return;
    }
    ctrl.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cur = _hits.isEmpty ? null : _hits[_current];
    // Chưa hỗ trợ CSV → PDF nên không hiện nút chuyển đổi với file .csv.
    final isCsv = docTypeFromPath(widget.path) == DocType.csv;
    return Scaffold(
      appBar: OfficeViewerAppBar(
        category: _category,
        title: p.basename(widget.path),
        actions: [
          IconButton(
            tooltip: l.office_search,
            icon: const Icon(Symbols.search_rounded),
            onPressed: () => setState(() => _searching = !_searching),
          ),
          IconButton(
            tooltip: l.office_zoomOut,
            icon: const Icon(Symbols.zoom_out_rounded),
            onPressed: () => _setZoom(_zoom - 0.25),
          ),
          IconButton(
            tooltip: l.office_zoomIn,
            icon: const Icon(Symbols.zoom_in_rounded),
            onPressed: () => _setZoom(_zoom + 0.25),
          ),
          if (!isCsv)
            IconButton(
              tooltip: l.office_convertToPdf,
              icon: const Icon(Symbols.picture_as_pdf_rounded),
              onPressed: () =>
                  context.push(Routes.excelToPdf, extra: widget.path),
            ),
        ],
      ),
      body: _sheets.isEmpty
          ? EmptyState(
              icon: Symbols.table_chart_rounded,
              title: l.office_emptySheet,
            )
          : Column(
              children: [
                if (_searching)
                  OfficeSearchBar(
                    category: _category,
                    controller: _searchCtrl,
                    onChanged: _onQuery,
                    current: _hits.isEmpty ? 0 : _current + 1,
                    total: _hits.length,
                    onPrev: () => _step(-1),
                    onNext: () => _step(1),
                    onClose: _closeSearch,
                  ),
                if (widget.truncated) OfficeNoticeBanner(l.office_truncated),
                Expanded(
                  child: PinchZoom(
                    scale: _zoom,
                    min: 0.5,
                    max: 3,
                    onScaleChanged: _setZoom,
                    child: XlsxSheetGrid(
                      key: ValueKey(_index),
                      sheet: _sheets[_index],
                      zoom: _zoom,
                      layout: _layoutOf(_index),
                      matches: _matchSet,
                      current: cur != null && cur.sheetIndex == _index
                          ? (cur.row, cur.col)
                          : null,
                      horizontalController: _hOf(_index),
                      verticalController: _vOf(_index),
                    ),
                  ),
                ),
                _SheetTabs(
                  names: [for (final s in _sheets) s.name],
                  selected: _index,
                  accent: officeHeaderColor(_category),
                  onSelected: (i) => setState(() {
                    _index = i;
                    _refreshMatchSet();
                  }),
                ),
              ],
            ),
    );
  }
}

/// Thanh tab sheet ở đáy: viên cao 32 cuộn ngang; tab chọn = nền màu loại file
/// (xanh cho XLSX, vàng cho CSV), chưa chọn = nền `surface2`.
class _SheetTabs extends StatelessWidget {
  const _SheetTabs({
    required this.names,
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final List<String> names;
  final int selected;
  final Color accent;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return OfficeBottomBar(
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: names.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final sel = i == selected;
            return Material(
              color: sel ? accent : t.surface2,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('sheetTab$i'),
                onTap: () => onSelected(i),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(maxWidth: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    names[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? Colors.white : t.text,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Lưới một sheet (hàng 0 / cột 0 là nhãn A, B, C / 1, 2, 3).
///
/// [matches] / [current]: toạ độ ô (row, col) 0-based cần tô sáng khi tìm kiếm.
/// [horizontalController] / [verticalController]: để trang cha cuộn tới ô.
class XlsxSheetGrid extends StatelessWidget {
  const XlsxSheetGrid({
    super.key,
    required this.sheet,
    this.zoom = 1,
    this.layout,
    this.matches = const {},
    this.current,
    this.horizontalController,
    this.verticalController,
  });

  final rd.XlsxSheet sheet;
  final double zoom;
  final XlsxGridLayout? layout;
  final Set<(int, int)> matches;
  final (int, int)? current;
  final ScrollController? horizontalController;
  final ScrollController? verticalController;

  @override
  Widget build(BuildContext context) {
    if (sheet.maxRow == 0 || sheet.maxCol == 0) {
      return Center(child: Text(context.l10n.office_emptySheet));
    }
    final layout = this.layout ?? XlsxGridLayout(sheet);
    return ColoredBox(
      color: Colors.white,
      child: TableView.builder(
        horizontalDetails: ScrollableDetails.horizontal(
          controller: horizontalController,
        ),
        verticalDetails: ScrollableDetails.vertical(
          controller: verticalController,
        ),
        diagonalDragBehavior: DiagonalDragBehavior.free,
        rowCount: layout.rowCount + 1,
        columnCount: layout.colCount + 1,
        pinnedRowCount: layout.pinnedRows + 1,
        pinnedColumnCount: layout.pinnedCols + 1,
        columnBuilder: (c) => TableSpan(
          extent: FixedTableSpanExtent(
            (c == 0 ? _headerColWidth : layout.columnWidth(c - 1)) * zoom,
          ),
        ),
        rowBuilder: (r) => TableSpan(
          extent: FixedTableSpanExtent(
            (r == 0 ? _headerRowHeight : layout.rowHeight(r - 1)) * zoom,
          ),
        ),
        cellBuilder: (context, v) {
          if (v.row == 0 || v.column == 0) {
            final label = v.row == 0 && v.column == 0
                ? ''
                : v.row == 0
                ? columnLabel(v.column - 1)
                : '${v.row}';
            return TableViewCell(child: _HeaderCell(label, zoom));
          }
          final r = v.row - 1, c = v.column - 1;
          final m = layout.mergeAt(r, c);
          final cr = m?.firstRow ?? r, cc = m?.firstCol ?? c;
          final cell = sheet.cell(cr, cc);
          final highlight = current == (cr, cc)
              ? XlsxHighlight.current
              : matches.contains((cr, cc))
              ? XlsxHighlight.match
              : XlsxHighlight.none;
          return TableViewCell(
            rowMergeStart: m == null ? null : m.firstRow + 1,
            rowMergeSpan: m?.rowSpan,
            columnMergeStart: m == null ? null : m.firstCol + 1,
            columnMergeSpan: m?.colSpan,
            child: XlsxCellView(cell: cell, zoom: zoom, highlight: highlight),
          );
        },
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, this.zoom);
  final String label;
  final double zoom;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: _headerBg,
      border: Border(
        right: BorderSide(color: _gridLine),
        bottom: BorderSide(color: _gridLine),
      ),
    ),
    child: Center(
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12 * zoom,
          color: Colors.black54,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

/// Một ô dữ liệu (luôn vẽ nền sáng, chữ đen giống Excel).
class XlsxCellView extends StatelessWidget {
  const XlsxCellView({
    super.key,
    required this.cell,
    required this.zoom,
    this.highlight = XlsxHighlight.none,
  });

  final rd.XlsxCell? cell;
  final double zoom;
  final XlsxHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final cell = this.cell;
    final style = cell?.style ?? rd.XlsxStyle.plain;
    final marked = highlight != XlsxHighlight.none;
    final fill = switch (highlight) {
      XlsxHighlight.current => _hitCurrent,
      XlsxHighlight.match => _hitMatch,
      XlsxHighlight.none =>
        style.fillArgb != null ? Color(style.fillArgb!) : Colors.white,
    };
    final fontColor = marked
        ? Colors.black87
        : style.fontColorArgb != null
        ? Color(style.fontColorArgb!)
        : contrastOn(fill);
    final border = BorderSide(
      color: style.hasBorder ? Colors.black87 : _gridLine,
      width: style.hasBorder ? 1 : 0.5,
    );

    final decorations = <TextDecoration>[
      if (style.underline) TextDecoration.underline,
      if (style.strike) TextDecoration.lineThrough,
    ];

    final hAlign = switch (style.hAlign) {
      rd.XlsxHAlign.left || rd.XlsxHAlign.justify => Alignment.centerLeft,
      rd.XlsxHAlign.center ||
      rd.XlsxHAlign.centerContinuous => Alignment.center,
      rd.XlsxHAlign.right => Alignment.centerRight,
      _ => switch (cell?.type) {
        rd.XlsxCellType.number || rd.XlsxCellType.date => Alignment.centerRight,
        rd.XlsxCellType.boolean || rd.XlsxCellType.error => Alignment.center,
        _ => Alignment.centerLeft,
      },
    };
    final vy = switch (style.vAlign) {
      rd.XlsxVAlign.top => -1.0,
      rd.XlsxVAlign.center => 0.0,
      _ => 1.0,
    };
    final alignment = Alignment(hAlign.x, vy);

    Widget? text;
    final display = cell?.display ?? '';
    if (display.isNotEmpty) {
      text = Text(
        display,
        softWrap: style.wrap,
        maxLines: style.wrap ? null : 1,
        overflow: TextOverflow.clip,
        textAlign: switch (hAlign.x) {
          < 0 => TextAlign.left,
          > 0 => TextAlign.right,
          _ => TextAlign.center,
        },
        style: TextStyle(
          fontSize: (style.fontSizePt ?? 11) * 4 / 3 * zoom,
          fontWeight: style.bold ? FontWeight.bold : null,
          fontStyle: style.italic ? FontStyle.italic : null,
          color: fontColor,
          decoration: decorations.isEmpty
              ? null
              : TextDecoration.combine(decorations),
          height: 1.1,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: Border(right: border, bottom: border),
      ),
      child: Container(
        alignment: alignment,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(),
        padding: EdgeInsets.fromLTRB(
          (3 + style.indent * 8) * zoom,
          1 * zoom,
          3 * zoom,
          1 * zoom,
        ),
        child: text,
      ),
    );
  }
}
