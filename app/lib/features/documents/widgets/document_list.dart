import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/doc_type.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/settings/settings_providers.dart';
import '../document_actions.dart';
import '../documents_logic.dart';
import '../documents_providers.dart';
import 'document_tile.dart';
import 'permission_views.dart';
import 'sort_menu.dart';

/// Khoảng cách của vùng nội dung tab Tập tin (điện thoại / máy tính bảng).
class _Spacing {
  const _Spacing(this.tablet);
  final bool tablet;

  double get side => tablet ? 24 : 16;
  double get top => tablet ? 18 : 14;
  double get bottom => tablet ? 28 : 24;

  /// Khoảng giữa các khối (băng quyền, lưới loại file, danh sách).
  double get gap => tablet ? 16 : 14;

  EdgeInsets get all => EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// Danh sách tài liệu của một tab Tập tin ([category] null = Tất cả).
///
/// Xử lý đủ trạng thái: đang quét (thanh tiến độ + "đã tìm N file" + skeleton), đang quét
/// có file (thanh mảnh trên đầu), thiếu quyền (màn xin quyền / băng nhắc), trống, lỗi;
/// kéo xuống để quét lại. Tab Tất cả có thêm lưới loại file ở đầu. Điện thoại: danh sách
/// trong một khối bo 20; máy tính bảng: lưới thẻ lớn.
class DocumentList extends ConsumerWidget {
  const DocumentList({super.key, required this.category, this.onPickCategory});

  final DocCategory? category;

  /// Bấm một ô trong lưới loại file → chuyển sang tab tương ứng. `null` = không hiện lưới.
  final ValueChanged<DocCategory>? onPickCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final tablet = isTabletLayout(context);
    final sp = _Spacing(tablet);
    // Chỉ dựng lại khi trạng thái quét đổi; số file đã tìm (đổi liên tục) do _ScanningView tự theo dõi.
    final (isScanning, needsPermission) = ref.watch(
      scanControllerProvider.select((s) => (s.isScanning, s.needsPermission)),
    );
    final bannerSnoozed = ref.watch(
      settingsProvider.select(
        (s) =>
            isStorageBannerSnoozed(s.storageBannerDismissedAt, DateTime.now()),
      ),
    );
    final docs = ref.watch(categoryDocumentsProvider(category));

    return docs.when(
      loading: () => DocumentListSkeleton(grid: tablet),
      error: (e, _) => EmptyState(
        icon: Symbols.error_rounded,
        title: appErrorMessage(context, AppError.from(e)),
        actionLabel: l.core_retry,
        onAction: () => ref.invalidate(documentsProvider),
      ),
      data: (items) {
        if (items.isEmpty && isScanning) return _ScanningView(tablet: tablet);
        final grid = onPickCategory == null
            ? null
            : CategoryGrid(onPick: onPickCategory!);
        return Column(
          children: [
            if (isScanning) _ThinScanBar(tablet: tablet),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(scanControllerProvider.notifier).refresh(),
                child: items.isEmpty
                    ? _EmptyScrollable(
                        spacing: sp,
                        top: needsPermission ? null : grid,
                        child: needsPermission
                            ? const _NoPermissionView()
                            : EmptyState(
                                illustration: _EmptyIllustration(
                                  category == null
                                      ? DocType.pdf
                                      : _typeOfCategory(category!),
                                ),
                                title: l.docs_emptyAll,
                                // App chỉ liệt kê thư mục của mình → mời chọn file từ máy.
                                actionLabel: l.core_selectFile,
                                onAction: () => pickAndOpenDocument(context),
                              ),
                      )
                    : CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              sp.side,
                              sp.top,
                              sp.side,
                              0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (needsPermission && !bannerSnoozed) ...[
                                    const PermissionBanner(),
                                    SizedBox(height: sp.gap),
                                  ],
                                  if (grid != null) ...[
                                    grid,
                                    SizedBox(height: sp.gap),
                                  ],
                                  _ListHeader(count: items.length),
                                  SizedBox(height: tablet ? 10 : 8),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              sp.side,
                              0,
                              sp.side,
                              sp.bottom,
                            ),
                            sliver: tablet
                                ? _CardGrid(items: items)
                                : SliverList.builder(
                                    itemCount: items.length,
                                    itemBuilder: (_, i) => CardRow(
                                      first: i == 0,
                                      last: i == items.length - 1,
                                      child: DocumentTile(items[i]),
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  static DocType _typeOfCategory(DocCategory c) => switch (c) {
    DocCategory.pdf => DocType.pdf,
    DocCategory.doc => DocType.docx,
    DocCategory.xls => DocType.xlsx,
    DocCategory.csv => DocType.csv,
    DocCategory.ppt => DocType.pptx,
    DocCategory.txt => DocType.txt,
  };
}

/// Hàng đầu danh sách: "N tài liệu" · nút chữ cách sắp xếp hiện tại ▾.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.docs_countDocs(count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.tokens.textMuted,
            ),
          ),
        ),
        const SortMenuButton.inline(),
      ],
    ),
  );
}

/// Lưới thẻ tài liệu (máy tính bảng): tự xếp cột, rộng tối thiểu 168 (dọc) / 180 (ngang).
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.items});

  final List<DocItem> items;

  static const double _gap = 14;

  @override
  Widget build(BuildContext context) {
    final minWidth =
        MediaQuery.orientationOf(context) == Orientation.landscape ? 180.0 : 168.0;
    final extent = DocumentCard.heightFor(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cols = math.max(
          1,
          ((constraints.crossAxisExtent + _gap) / (minWidth + _gap)).floor(),
        );
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            mainAxisExtent: extent,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => DocumentCard(items[i]),
        );
      },
    );
  }
}

/// Trạng thái trống / chưa có quyền vẫn kéo xuống để quét lại được; [top] (lưới loại file)
/// nằm trên, phần còn lại căn giữa.
class _EmptyScrollable extends StatelessWidget {
  const _EmptyScrollable({required this.spacing, required this.child, this.top});

  final _Spacing spacing;
  final Widget child;
  final Widget? top;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      if (top != null)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            spacing.side,
            spacing.top,
            spacing.side,
            0,
          ),
          sliver: SliverToBoxAdapter(child: top),
        ),
      SliverFillRemaining(hasScrollBody: false, child: Center(child: child)),
    ],
  );
}

/// Chưa có quyền và chưa có file: màn xin quyền + nút viền "Chọn file thủ công".
class _NoPermissionView extends StatelessWidget {
  const _NoPermissionView();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const PermissionGate(),
      // EmptyState chừa sẵn 40 dưới nút "Cấp quyền"; kéo nút này lên để hai nút cách nhau
      // 10 như thiết kế (Transform giữ đúng vùng chạm).
      Transform.translate(
        offset: const Offset(0, -30),
        child: const PickFileButton(),
      ),
    ],
  );
}

/// Minh hoạ trống: tờ giấy viền mờ nghiêng phía sau + icon loại file của tab.
class _EmptyIllustration extends StatelessWidget {
  const _EmptyIllustration(this.type);

  final DocType type;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        children: [
          Positioned(
            left: 30,
            top: 30,
            child: Transform.rotate(
              angle: -10 * math.pi / 180,
              child: Container(
                width: 40,
                height: 52,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: t.lineStrong, width: 2),
                ),
              ),
            ),
          ),
          Positioned(left: 52, top: 34, child: FileTypeIcon(type, size: 50)),
        ],
      ),
    );
  }
}

/// Thanh tiến độ mảnh 3px khi đang quét mà đã có file để hiện.
class _ThinScanBar extends StatelessWidget {
  const _ThinScanBar({required this.tablet});

  final bool tablet;

  @override
  Widget build(BuildContext context) => Padding(
    padding: tablet
        ? const EdgeInsets.fromLTRB(28, 10, 28, 0)
        : EdgeInsets.zero,
    child: LinearProgressIndicator(
      minHeight: 3,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

/// Đang quét và chưa có file: thanh tiến độ 4px + "Đang quét… đã tìm N file" + skeleton.
class _ScanningView extends StatelessWidget {
  const _ScanningView({required this.tablet});

  final bool tablet;

  @override
  Widget build(BuildContext context) => ListView(
    padding: _Spacing(tablet).all,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            const _FoundCount(),
          ],
        ),
      ),
      SizedBox(height: tablet ? 14 : 12),
      _SkeletonBlock(grid: tablet),
    ],
  );
}

/// Chỉ dòng chữ này theo dõi số file đã tìm (đổi liên tục), phần còn lại không dựng lại.
class _FoundCount extends ConsumerWidget {
  const _FoundCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    context.l10n.docs_scanning(
      ref.watch(scanControllerProvider.select((s) => s.found)),
    ),
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: context.tokens.textMuted,
    ),
  );
}

/// Khung xương hiện lúc chưa có dữ liệu ([grid] = thẻ lớn của máy tính bảng).
class DocumentListSkeleton extends StatelessWidget {
  const DocumentListSkeleton({super.key, this.grid = false});

  final bool grid;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: _Spacing(grid).all,
    children: [_SkeletonBlock(grid: grid)],
  );
}

/// 8 dòng xương trong khối nền trắng bo 20, hoặc 8 thẻ xương (máy tính bảng).
class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.grid});

  final bool grid;

  static const _w1 = [0.72, 0.58, 0.80, 0.64, 0.50, 0.76, 0.60, 0.68];
  static const _w2 = [0.40, 0.34, 0.46, 0.30, 0.38, 0.42, 0.28, 0.36];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
    Widget lines(int i) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(_w1[i], 11), const SizedBox(height: 7), bar(_w2[i], 9)],
    );

    if (grid) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const gap = 14.0;
          final cols = math.max(
            1,
            ((constraints.maxWidth + gap) / (168 + gap)).floor(),
          );
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              mainAxisExtent: 120 + 28 + 27,
            ),
            itemCount: 8,
            itemBuilder: (_, i) => Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: 120, color: t.surface2),
                  Padding(padding: const EdgeInsets.all(14), child: lines(i)),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (var i = 0; i < 8; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: lines(i)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Lưới loại file ở đầu tab Tất cả: PDF · DOC · XLS · CSV · PPT · TXT · Khác.
/// Điện thoại: 7 ô trong một khối bo 20; máy tính bảng: 7 thẻ rời có viền.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, required this.onPick});

  final ValueChanged<DocCategory> onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tablet = isTabletLayout(context);

    final cells = <(DocType, String, VoidCallback, String)>[
      (DocType.pdf, 'PDF', () => onPick(DocCategory.pdf), 'grid-pdf'),
      (DocType.docx, 'DOC', () => onPick(DocCategory.doc), 'grid-doc'),
      (DocType.xlsx, 'XLS', () => onPick(DocCategory.xls), 'grid-xls'),
      (DocType.csv, 'CSV', () => onPick(DocCategory.csv), 'grid-csv'),
      (DocType.pptx, 'PPT', () => onPick(DocCategory.ppt), 'grid-ppt'),
      (DocType.txt, 'TXT', () => onPick(DocCategory.txt), 'grid-txt'),
      (
        DocType.other,
        l.docs_categoryMore,
        () => pickAndOpenDocument(context),
        'grid-more',
      ),
    ];

    Widget cell((DocType, String, VoidCallback, String) c) {
      final (type, label, onTap, key) = c;
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FileTypeIcon(type, size: 40),
          SizedBox(height: tablet ? 8 : 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: tablet ? 12.5 : 12,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
        ],
      );
      if (tablet) {
        return Material(
          color: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: t.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
              child: content,
            ),
          ),
        );
      }
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: content,
          ),
        ),
      );
    }

    if (tablet) {
      return Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: cell(cells[i])),
          ],
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          for (final c in cells)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: cell(c),
              ),
            ),
        ],
      ),
    );
  }
}
