import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n/l10n.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/doc_type.dart';
import '../../core/widgets/widgets.dart';
import 'documents_providers.dart';
import 'widgets/document_list.dart';
import 'widgets/home_drawer.dart';
import 'widgets/sort_menu.dart';

/// Thứ tự tab Tập tin: Tất cả · PDF · DOC · XLS · CSV · PPT · TXT (`null` = Tất cả).
const List<DocCategory?> homeTabs = [
  null,
  DocCategory.pdf,
  DocCategory.doc,
  DocCategory.xls,
  DocCategory.csv,
  DocCategory.ppt,
  DocCategory.txt,
];

/// Thời gian đổi màu khối tiêu đề khi chuyển tab.
const Duration _headerColorDuration = Duration(milliseconds: 250);

/// Tab "Tập tin": khối tiêu đề màu theo tab (không dùng AppBar) với hàng "viên" loại file,
/// rồi danh sách tài liệu vuốt ngang được giữa các tab.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs = TabController(
    length: homeTabs.length,
    vsync: this,
  )..addListener(_onTabChanged);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.dispose();
    super.dispose();
  }

  int _shownIndex = 0;

  /// Chỉ dựng lại khối tiêu đề khi tab thật sự đổi (listener bắn nhiều lần lúc vuốt).
  void _onTabChanged() {
    if (_tabs.index == _shownIndex) return;
    setState(() => _shownIndex = _tabs.index);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quay lại app (có thể vừa cấp quyền trong Cài đặt / có file mới) → quét lại.
    if (state == AppLifecycleState.resumed) {
      ref.read(scanControllerProvider.notifier).refresh(force: false);
    }
  }

  void _goToCategory(DocCategory category) =>
      _tabs.animateTo(homeTabs.indexOf(category));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tablet = isTabletLayout(context);
    final headerColor =
        AppColors.headerForCategory(homeTabs[_shownIndex]) ?? t.filesAllHeader;
    // Khởi động lượt quét đầu tiên.
    ref.watch(scanControllerProvider.select((s) => s.phase == ScanPhase.idle));

    // Điện thoại: khối tiêu đề màu nằm dưới thanh trạng thái → icon trạng thái trắng.
    // Máy tính bảng: khối tiêu đề tách khỏi mép trên, thanh trạng thái nằm trên nền màn.
    final overlay = !tablet || Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: t.bg,
        // Máy tính bảng bỏ ngăn kéo: lối tắt nằm ở thanh bên, cài đặt ở tab Cài đặt.
        drawer: tablet ? null : const HomeDrawer(),
        body: Column(
          children: [
            _FilesHeader(
              color: headerColor,
              tablet: tablet,
              selected: _shownIndex,
              onSelect: (i) => _tabs.animateTo(i),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  for (final category in homeTabs)
                    DocumentList(
                      category: category,
                      onPickCategory: category == null ? _goToCategory : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Khối tiêu đề Tập tin: ☰ (chỉ điện thoại) · "Tập tin" · ⭐ · 🕘 · 🔍 · ⇅, dưới là hàng viên
/// loại file cuộn ngang. Điện thoại: tràn mép trên, bo dưới 26; máy tính bảng: thẻ bo 26.
class _FilesHeader extends StatelessWidget {
  const _FilesHeader({
    required this.color,
    required this.tablet,
    required this.selected,
    required this.onSelect,
  });

  final Color color;
  final bool tablet;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final buttonSize = tablet ? const Size(44, 44) : const Size(40, 44);
    Widget action(String key, IconData icon, String tooltip, String route) =>
        IconButton(
          key: ValueKey(key),
          tooltip: tooltip,
          style: _headerIconStyle(buttonSize),
          icon: Icon(icon, size: 23, color: Colors.white),
          onPressed: () => context.push(route),
        );

    final titleRow = Row(
      children: [
        if (!tablet)
          IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            style: _headerIconStyle(const Size(44, 44)),
            icon: const Icon(Symbols.menu_rounded, size: 24, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: tablet ? 0 : 2),
            child: Text(
              l.docs_navFiles,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: tablet ? 24 : 21,
                fontWeight: tablet ? FontWeight.w800 : FontWeight.w700,
                letterSpacing: tablet ? -0.24 : -0.21,
                color: Colors.white,
              ),
            ),
          ),
        ),
        action(
          'home-favorites',
          Symbols.star_rounded,
          l.docs_favorites,
          Routes.favorites,
        ),
        action(
          'home-recents',
          Symbols.history_rounded,
          l.docs_recents,
          Routes.recents,
        ),
        action(
          'home-search',
          Symbols.search_rounded,
          l.docs_searchHint,
          Routes.search,
        ),
        SortMenuButton(iconColor: Colors.white, buttonSize: buttonSize),
      ],
    );

    final labels = [l.docs_tabAll, 'PDF', 'DOC', 'XLS', 'CSV', 'PPT', 'TXT'];
    Widget pills(EdgeInsets padding) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _TabPill(
              key: ValueKey('files-tab-$i'),
              label: labels[i],
              selected: i == selected,
              headerColor: color,
              tablet: tablet,
              onTap: () => onSelect(i),
            ),
          ],
        ],
      ),
    );

    if (tablet) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: AnimatedContainer(
            key: const ValueKey('files-header'),
            duration: _headerColorDuration,
            padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleRow,
                const SizedBox(height: 12),
                pills(EdgeInsets.zero),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      key: const ValueKey('files-header'),
      duration: _headerColorDuration,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: titleRow,
              ),
              pills(const EdgeInsets.fromLTRB(16, 8, 16, 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút icon trắng trên khối tiêu đề, cỡ đúng thiết kế (không nới ra 48).
ButtonStyle _headerIconStyle(Size size) => IconButton.styleFrom(
  foregroundColor: Colors.white,
  fixedSize: size,
  minimumSize: size,
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Một "viên" loại file: đang chọn = nền trắng chữ màu tiêu đề; chưa chọn = trắng 16%.
class _TabPill extends StatelessWidget {
  const _TabPill({
    super.key,
    required this.label,
    required this.selected,
    required this.headerColor,
    required this.tablet,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color headerColor;
  final bool tablet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final height = tablet ? 38.0 : 36.0;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: tablet ? 18 : 16),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: tablet ? 14 : 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? headerColor : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
