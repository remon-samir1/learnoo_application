import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;

class PaginationBar extends StatelessWidget {
  final int currentPage;
  final int lastPage;
  final bool hasNextPage;
  final bool isLoading;
  final ValueChanged<int> onPageChanged;
  final Color primaryColor;
  final bool hideIfSinglePage;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.lastPage,
    this.hasNextPage = false,
    this.isLoading = false,
    required this.onPageChanged,
    this.primaryColor = const Color(0xFF4A68F6),
    this.hideIfSinglePage = false,
  });

  bool get _hasPrev => currentPage > 1;
  bool get _hasNext => currentPage < lastPage || hasNextPage;
  int get _effectiveLast =>
      lastPage > 0 ? lastPage : (hasNextPage ? currentPage + 1 : currentPage);

  List<dynamic> _buildPageItems() {
    final effectiveLast = _effectiveLast;
    if (effectiveLast <= 1) return [1];

    if (effectiveLast <= 5) {
      return List.generate(effectiveLast, (i) => i + 1);
    }

    final items = <dynamic>[];
    items.add(1);

    if (currentPage > 3) {
      items.add('...');
    }

    final start = (currentPage - 1).clamp(2, effectiveLast - 1);
    final end = (currentPage + 1).clamp(2, effectiveLast - 1);

    for (int p = start; p <= end; p++) {
      if (!items.contains(p)) {
        items.add(p);
      }
    }

    if (currentPage < effectiveLast - 2) {
      items.add('...');
    }

    if (!items.contains(effectiveLast)) {
      items.add(effectiveLast);
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLast = _effectiveLast;
    if (effectiveLast <= 1 && !hasNextPage && hideIfSinglePage) {
      return const SizedBox.shrink();
    }

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final prevIcon =
        isRtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
    final nextIcon =
        isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;

    final pageItems = _buildPageItems();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFF1F1F1)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous Button
              _buildNavButton(
                icon: prevIcon,
                enabled: _hasPrev && !isLoading,
                onTap: () => onPageChanged(currentPage - 1),
              ),
              const SizedBox(width: 8),

              // Page Numbers
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: pageItems.map((item) {
                      if (item is int) {
                        final isSelected = item == currentPage;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildPageButton(
                            page: item,
                            isSelected: isSelected,
                            onTap: () {
                              if (!isSelected && !isLoading) {
                                onPageChanged(item);
                              }
                            },
                          ),
                        );
                      } else {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '...',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Next Button
              _buildNavButton(
                icon: nextIcon,
                enabled: _hasNext && !isLoading,
                onTap: () => onPageChanged(currentPage + 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'course.page_of'.tr(
              args: [currentPage.toString(), effectiveLast.toString()],
            ),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled ? Colors.white : const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? const Color(0xFFE5E7EB) : const Color(0xFFF3F4F6),
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: enabled ? primaryColor : const Color(0xFFD1D5DB),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageButton({
    required int page,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? primaryColor : Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: isSelected ? 2 : 0,
      shadowColor: isSelected ? primaryColor.withValues(alpha: 0.4) : Colors.transparent,
      child: InkWell(
        onTap: isSelected ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? null
                : Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Center(
            child: Text(
              '$page',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF374151),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
