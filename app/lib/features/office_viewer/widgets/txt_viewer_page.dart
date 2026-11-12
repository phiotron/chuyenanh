import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/doc_type.dart';
import '../data/text_decoder.dart';
import '../logic/text_search.dart';
import 'office_common.dart';

/// Cỡ chữ TXT (giữ trong phiên).
class TxtFontSize extends Notifier<double> {
  @override
  double build() => 16;

  void set(double v) => state = v.clamp(10, 40).toDouble();
}

final txtFontSizeProvider = NotifierProvider<TxtFontSize, double>(
  TxtFontSize.new,
);

/// Màn xem TXT: danh sách dòng, chụm để đổi cỡ chữ, tìm chữ, chuyển sang PDF.
class TxtViewerPage extends ConsumerStatefulWidget {
  const TxtViewerPage({super.key, required this.path, required this.content});

  final String path;
  final DecodedText content;

  @override
  ConsumerState<TxtViewerPage> createState() => _TxtViewerPageState();
}

class _TxtViewerPageState extends ConsumerState<TxtViewerPage> {
  List<String> _lines = const [];
  bool _loading = true;
  Timer? _debounce;
  int _seq = 0;
  final _scroller = IndexedScroller();
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<SearchHit> _hits = const [];
  int _current = 0;

  bool get _large => widget.content.text.length > largeTextChars;

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    final text = widget.content.text;
    if (text.length <= largeTextChars) {
      _lines = splitLinesCapped(text);
      _loading = false;
      return;
    }
    final lines = await Isolate.run(() => splitLinesCapped(text));
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    final seq = ++_seq;
    if (!_large) {
      _applyHits(findHitsLimited(_lines, q));
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final lines = _lines;
      final r = await Isolate.run(() => findHitsLimited(lines, q));
      if (!mounted || seq != _seq) return;
      _applyHits(r);
    });
  }

  void _applyHits(({List<SearchHit> hits, bool truncated}) r) {
    setState(() {
      _hits = r.hits;
      _current = 0;
    });
    _goToCurrent();
  }

  void _step(int delta) {
    if (_hits.isEmpty) return;
    setState(() => _current = (_current + delta) % _hits.length);
    if (_current < 0) _current += _hits.length;
    _goToCurrent();
  }

  void _goToCurrent() {
    if (_hits.isEmpty) return;
    _scroller.jumpTo(_hits[_current].block, _lines.length);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final fontSize = ref.watch(txtFontSizeProvider);
    final t = context.tokens;
    final notifier = ref.read(txtFontSizeProvider.notifier);
    final query = _searchCtrl.text;
    final curHit = _hits.isEmpty ? null : _hits[_current];

    return Scaffold(
      appBar: OfficeViewerAppBar(
        category: DocCategory.txt,
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
            onPressed: () => notifier.set(fontSize - 2),
          ),
          IconButton(
            tooltip: l.office_zoomIn,
            icon: const Icon(Symbols.zoom_in_rounded),
            onPressed: () => notifier.set(fontSize + 2),
          ),
          IconButton(
            tooltip: l.office_convertToPdf,
            icon: const Icon(Symbols.picture_as_pdf_rounded),
            onPressed: () => context.push(Routes.textToPdf, extra: widget.path),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            OfficeSearchBar(
              category: DocCategory.txt,
              controller: _searchCtrl,
              onChanged: _onQuery,
              current: _hits.isEmpty ? 0 : _current + 1,
              total: _hits.length,
              onPrev: () => _step(-1),
              onNext: () => _step(1),
              onClose: () => setState(() {
                _debounce?.cancel();
                _seq++;
                _searching = false;
                _searchCtrl.clear();
                _hits = const [];
              }),
            ),
          if (widget.content.truncated) OfficeNoticeBanner(l.office_truncated),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: officeHeaderColor(DocCategory.txt),
                    ),
                  )
                : PinchZoom(
                    scale: fontSize / 16,
                    min: 10 / 16,
                    max: 40 / 16,
                    onScaleChanged: (s) => notifier.set(16 * s),
                    child: SelectionArea(
                      child: ListView.builder(
                        controller: _scroller.controller,
                        padding: const EdgeInsets.all(12),
                        itemCount: _lines.length,
                        itemBuilder: (context, i) => KeyedSubtree(
                          key: _scroller.keyFor(i),
                          child: _Line(
                            text: _lines[i],
                            query: _searching ? query : '',
                            currentStart: curHit != null && curHit.block == i
                                ? curHit.start
                                : null,
                            style: TextStyle(fontSize: fontSize, height: 1.4),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          OfficeBottomBar(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                l.office_encodingLabel(widget.content.encoding.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: t.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.text,
    required this.query,
    required this.currentStart,
    required this.style,
  });

  final String text;
  final String query;
  final int? currentStart;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return Text(' ', style: style);
    if (query.trim().isEmpty) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        children: [
          for (final s in highlightSegments(text, query))
            TextSpan(
              text: s.text,
              style: s.matched
                  ? TextStyle(
                      backgroundColor: s.start == currentStart
                          ? Colors.orange
                          : Colors.yellow,
                      color: Colors.black,
                    )
                  : null,
            ),
        ],
      ),
      style: style,
    );
  }
}
