import 'package:flutter/material.dart';

/// A resizable split screen widget that allows two panels to be displayed
/// side by side (horizontal) or stacked (vertical)
class SplitScreenView extends StatefulWidget {
  final Widget topOrLeftPanel;
  final Widget bottomOrRightPanel;
  final double initialSplitRatio;
  final double minSplitRatio;
  final double maxSplitRatio;
  final Axis direction;
  final bool resizable;
  final Color dividerColor;
  final double dividerThickness;
  final Widget? dividerHandle;

  const SplitScreenView({
    super.key,
    required this.topOrLeftPanel,
    required this.bottomOrRightPanel,
    this.initialSplitRatio = 0.5,
    this.minSplitRatio = 0.2,
    this.maxSplitRatio = 0.8,
    this.direction = Axis.vertical,
    this.resizable = true,
    this.dividerColor = const Color(0xFFE5E7EB),
    this.dividerThickness = 4.0,
    this.dividerHandle,
  }) : assert(initialSplitRatio >= minSplitRatio && initialSplitRatio <= maxSplitRatio);

  @override
  State<SplitScreenView> createState() => _SplitScreenViewState();
}

class _SplitScreenViewState extends State<SplitScreenView> {
  late double _splitRatio;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _splitRatio = widget.initialSplitRatio;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.resizable) return;

    final size = context.size;
    if (size == null) return;

    setState(() {
      if (widget.direction == Axis.vertical) {
        _splitRatio += details.delta.dy / size.height;
      } else {
        _splitRatio += details.delta.dx / size.width;
      }

      // Clamp to min/max bounds
      _splitRatio = _splitRatio.clamp(widget.minSplitRatio, widget.maxSplitRatio);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVertical = widget.direction == Axis.vertical;
        final firstSize = isVertical
            ? constraints.maxHeight * _splitRatio
            : constraints.maxWidth * _splitRatio;

        return isVertical
            ? _buildVerticalLayout(firstSize)
            : _buildHorizontalLayout(firstSize);
      },
    );
  }

  Widget _buildVerticalLayout(double topHeight) {
    return Column(
      children: [
        SizedBox(
          height: topHeight,
          child: widget.topOrLeftPanel,
        ),
        _buildDivider(),
        Expanded(
          child: widget.bottomOrRightPanel,
        ),
      ],
    );
  }

  Widget _buildHorizontalLayout(double leftWidth) {
    return Row(
      children: [
        SizedBox(
          width: leftWidth,
          child: widget.topOrLeftPanel,
        ),
        _buildDivider(),
        Expanded(
          child: widget.bottomOrRightPanel,
        ),
      ],
    );
  }

  Widget _buildDivider() {
    final isVertical = widget.direction == Axis.vertical;

    return GestureDetector(
      onHorizontalDragStart: (_) => setState(() => _isDragging = true),
      onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
      onHorizontalDragUpdate: isVertical ? null : _handleDragUpdate,
      onVerticalDragStart: (_) => setState(() => _isDragging = true),
      onVerticalDragEnd: (_) => setState(() => _isDragging = false),
      onVerticalDragUpdate: isVertical ? _handleDragUpdate : null,
      child: MouseRegion(
        cursor: widget.resizable
            ? (isVertical ? SystemMouseCursors.resizeRow : SystemMouseCursors.resizeColumn)
            : SystemMouseCursors.basic,
        child: Container(
          width: isVertical ? double.infinity : widget.dividerThickness,
          height: isVertical ? widget.dividerThickness : double.infinity,
          color: _isDragging ? const Color(0xFF5A75FF) : widget.dividerColor,
          child: Center(
            child: widget.dividerHandle ?? _defaultHandle(isVertical),
          ),
        ),
      ),
    );
  }

  Widget _defaultHandle(bool isVertical) {
    return Container(
      width: isVertical ? 40 : 16,
      height: isVertical ? 4 : 40,
      decoration: BoxDecoration(
        color: _isDragging ? const Color(0xFF5A75FF) : Colors.grey[400],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Pre-configured split screen for Video and PDF content
class VideoPdfSplitScreen extends StatelessWidget {
  final Widget videoWidget;
  final Widget pdfWidget;
  final bool resizable;
  final double initialVideoRatio;

  const VideoPdfSplitScreen({
    super.key,
    required this.videoWidget,
    required this.pdfWidget,
    this.resizable = true,
    this.initialVideoRatio = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return SplitScreenView(
      direction: isLandscape ? Axis.horizontal : Axis.vertical,
      initialSplitRatio: initialVideoRatio,
      minSplitRatio: 0.25,
      maxSplitRatio: 0.75,
      resizable: resizable,
      topOrLeftPanel: _PanelContainer(
        label: 'Video',
        icon: Icons.play_circle_outline,
        child: videoWidget,
      ),
      bottomOrRightPanel: _PanelContainer(
        label: 'PDF Document',
        icon: Icons.picture_as_pdf,
        child: pdfWidget,
      ),
    );
  }
}

/// Container for split screen panels with optional header
class _PanelContainer extends StatelessWidget {
  final Widget child;
  final String label;
  final IconData icon;

  const _PanelContainer({
    required this.child,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          // Panel content
          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Tab-based alternative for mobile devices
class ContentTabView extends StatefulWidget {
  final Widget videoContent;
  final Widget pdfContent;
  final String videoLabel;
  final String pdfLabel;

  const ContentTabView({
    super.key,
    required this.videoContent,
    required this.pdfContent,
    this.videoLabel = 'Video',
    this.pdfLabel = 'PDF',
  });

  @override
  State<ContentTabView> createState() => _ContentTabViewState();
}

class _ContentTabViewState extends State<ContentTabView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF5A75FF),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF5A75FF),
            tabs: [
              Tab(
                icon: const Icon(Icons.play_circle_outline),
                text: widget.videoLabel,
              ),
              Tab(
                icon: const Icon(Icons.picture_as_pdf),
                text: widget.pdfLabel,
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              widget.videoContent,
              widget.pdfContent,
            ],
          ),
        ),
      ],
    );
  }
}

/// Adaptive widget that shows split screen on large devices and tabs on small devices
class AdaptiveSplitView extends StatelessWidget {
  final Widget videoContent;
  final Widget pdfContent;
  final double breakpoint;

  const AdaptiveSplitView({
    super.key,
    required this.videoContent,
    required this.pdfContent,
    this.breakpoint = 800,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth >= breakpoint) {
      return VideoPdfSplitScreen(
        videoWidget: videoContent,
        pdfWidget: pdfContent,
      );
    }

    return ContentTabView(
      videoContent: videoContent,
      pdfContent: pdfContent,
    );
  }
}
