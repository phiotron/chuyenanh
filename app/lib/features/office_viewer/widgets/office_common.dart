import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/doc_type.dart';
import '../../../core/widgets/app_search_field.dart';

/// Băng báo dưới thanh tiêu đề (vd. "File lớn, chỉ hiển thị phần đầu."):
/// nền `surface`, kẻ dưới `line`, icon thông tin + chữ 13.
class OfficeNoticeBanner extends StatelessWidget {
  const OfficeNoticeBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          Icon(Symbols.info_rounded, size: 18, color: t.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: t.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Màu thanh tiêu đề trình xem theo loại file (bản đậm, `design-mobile/README.md` §1.2):
/// DOC `#1565C0` · XLS `#2E7D32` · PPT `#D84315` · TXT `#546E7A`; chữ/icon trắng.
Color officeHeaderColor(DocCategory category) =>
    AppColors.headerForCategory(category) ?? AppColors.primary;

/// Thanh tiêu đề chung của các trình xem Office/TXT: nền màu theo loại file, chữ/icon trắng.
///
/// Theme AppBar mặc định là nền sáng nên đặt rõ nền, chữ, icon và thanh trạng thái sáng.
class OfficeViewerAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const OfficeViewerAppBar({
    super.key,
    required this.category,
    required this.title,
    this.actions,
  });

  final DocCategory category;

  /// Thường là tên file; dài thì cắt "…".
  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    const onBar = IconThemeData(color: Colors.white);
    return AppBar(
      backgroundColor: officeHeaderColor(category),
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: onBar,
      actionsIconTheme: onBar,
      titleTextStyle: const TextStyle(
        fontFamily: kUiFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: actions,
    );
  }
}

/// Thanh đáy chung của trình xem (tab sheet XLSX, "Bảng mã" TXT, dải thumbnail PPTX):
/// nền `surface`, kẻ trên bằng `line`, chừa vùng an toàn phía dưới.
class OfficeBottomBar extends StatelessWidget {
  const OfficeBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// Bắt thao tác chụm 2 ngón để phóng to / thu nhỏ mà không tranh cử chỉ với cuộn
/// (dùng [Listener], không vào arena cử chỉ).
class PinchZoom extends StatefulWidget {
  const PinchZoom({
    super.key,
    required this.scale,
    required this.onScaleChanged,
    required this.child,
    this.min = 0.5,
    this.max = 4,
  });

  final double scale;
  final ValueChanged<double> onScaleChanged;
  final double min;
  final double max;
  final Widget child;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> {
  final Map<int, Offset> _pointers = {};
  double? _baseDistance;
  double _baseScale = 1;

  double? get _distance {
    if (_pointers.length < 2) return null;
    final p = _pointers.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _pointers[e.pointer] = e.position;
        if (_pointers.length == 2) {
          _baseDistance = _distance;
          _baseScale = widget.scale;
        }
      },
      onPointerMove: (e) {
        if (!_pointers.containsKey(e.pointer)) return;
        _pointers[e.pointer] = e.position;
        final d = _distance;
        final base = _baseDistance;
        if (d != null && base != null && base > 10) {
          final next = (_baseScale * d / base).clamp(widget.min, widget.max);
          if ((next - widget.scale).abs() > 0.01) {
            widget.onScaleChanged(next.toDouble());
          }
        }
      },
      onPointerUp: (e) {
        _pointers.remove(e.pointer);
        _baseDistance = null;
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        _baseDistance = null;
      },
      child: widget.child,
    );
  }
}

/// Thanh tìm chữ: ô nhập + "n/m" + trước/sau + đóng. Nằm ngay dưới thanh tiêu đề, cùng màu.
class OfficeSearchBar extends StatelessWidget {
  const OfficeSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.current,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
    this.category,
    this.color,
  });

  /// Loại file → nền = [officeHeaderColor] (trùng thanh tiêu đề [OfficeViewerAppBar]).
  final DocCategory? category;

  /// Nền đặt tay (ưu tiên hơn [category]); cả hai null → đỏ chủ đạo.
  final Color? color;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// 1-based; 0 khi chưa có kết quả.
  final int current;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final hasQuery = controller.text.trim().isNotEmpty;
    final category = this.category;
    final bg =
        color ??
        (category == null ? AppColors.primary : officeHeaderColor(category));
    return Material(
      color: bg,
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: controller,
                  hintText: l.office_searchHint,
                  onChanged: onChanged,
                  onSubmitted: (_) => onNext(),
                ),
              ),
              if (hasQuery)
                Text(
                  total == 0
                      ? l.office_noResults
                      : l.office_matchCount(current, total),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              IconButton(
                tooltip: l.office_prevMatch,
                icon: const Icon(Symbols.keyboard_arrow_up_rounded),
                color: Colors.white,
                disabledColor: Colors.white38,
                onPressed: total == 0 ? null : onPrev,
              ),
              IconButton(
                tooltip: l.office_nextMatch,
                icon: const Icon(Symbols.keyboard_arrow_down_rounded),
                color: Colors.white,
                disabledColor: Colors.white38,
                onPressed: total == 0 ? null : onNext,
              ),
              IconButton(
                tooltip: l.core_close,
                icon: const Icon(Symbols.close_rounded),
                color: Colors.white,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cuộn tới mục thứ i của `ListView.builder` (mục chưa dựng: nhảy ước lượng rồi tinh chỉnh).
/// Mỗi mục phải bọc bằng `KeyedSubtree(key: scroller.keyFor(i), ...)`.
class IndexedScroller {
  final ScrollController controller = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  GlobalKey keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  Future<void> jumpTo(int index, int count, {double alignment = 0.3}) async {
    for (var n = 0; n < 8; n++) {
      final ctx = _keys[index]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: alignment,
          duration: const Duration(milliseconds: 180),
        );
        return;
      }
      if (!controller.hasClients || count <= 0) return;
      final max = controller.position.maxScrollExtent;
      controller.jumpTo(math.min(max, max * index / count));
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  void dispose() => controller.dispose();
}

/// Màu chữ tương phản với nền [bg].
Color contrastOn(Color bg) =>
    ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
    ? Colors.white
    : Colors.black;
