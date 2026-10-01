import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/poll_model.dart';
import '../models/wheel_model.dart';
import '../services/api_service.dart';

typedef WheelAction = Future<void> Function(
  Future<void> Function(ApiService api) action,
);

class _WheelGraphic extends StatefulWidget {
  const _WheelGraphic({
    required this.items,
    required this.selectedId,
    required this.spinId,
    required this.onSpinComplete,
    required this.animateOnMount,
  });

  final List<({String id, String name})> items;
  final String? selectedId;
  final String? spinId;
  final VoidCallback onSpinComplete;
  final bool animateOnMount;

  @override
  State<_WheelGraphic> createState() => _WheelGraphicState();
}

class _WheelGraphicState extends State<_WheelGraphic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _turn;
  double _rotation = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3200),
        )..addListener(() {
          setState(() => _rotation = _turn.value);
        });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onSpinComplete();
    });
    _rotation = _selectedRotation();
    _turn = AlwaysStoppedAnimation(_rotation);
    if (widget.animateOnMount) _startSpin();
  }

  double _selectedRotation() {
    final index = widget.items.indexWhere(
      (item) => item.id == widget.selectedId,
    );
    if (index < 0 || widget.items.isEmpty) return 0;
    final slice = 2 * math.pi / widget.items.length;
    return (2 * math.pi - (index + 0.5) * slice) % (2 * math.pi);
  }

  @override
  void didUpdateWidget(covariant _WheelGraphic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinId == null || widget.spinId == oldWidget.spinId) return;
    if (!widget.items.any((item) => item.id == widget.selectedId)) return;
    _startSpin();
  }

  void _startSpin() {
    final target = _selectedRotation();
    final begin = _rotation;
    final remaining = (target - begin) % (2 * math.pi);
    _controller.stop();
    _turn = Tween<double>(
      begin: begin,
      end: begin + 4 * 2 * math.pi + remaining,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _WheelPainter(
      items: widget.items,
      selectedId: _controller.isAnimating ? null : widget.selectedId,
      rotation: _rotation,
      accent: Theme.of(context).colorScheme.primary,
      centerColor: Theme.of(context).colorScheme.surface,
      labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
      colors: [
        Theme.of(context).colorScheme.primaryContainer,
        Theme.of(context).colorScheme.secondaryContainer,
        Theme.of(context).colorScheme.tertiaryContainer,
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ],
    ),
    child: const SizedBox.expand(),
  );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({
    required this.items,
    required this.selectedId,
    required this.rotation,
    required this.accent,
    required this.centerColor,
    required this.labelColor,
    required this.colors,
  });

  final List<({String id, String name})> items;
  final String? selectedId;
  final double rotation;
  final Color accent;
  final Color centerColor;
  final Color labelColor;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final slice = 2 * math.pi / items.length;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    for (var i = 0; i < items.length; i++) {
      final start = -math.pi / 2 + i * slice;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      canvas.drawArc(bounds, start, slice, true, paint);
      canvas.drawArc(
        bounds,
        start,
        slice,
        true,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (items[i].id == selectedId) {
        canvas.drawArc(
          bounds,
          start,
          slice,
          true,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }
      final middle = start + slice / 2;
      final labelRadius = radius * 0.57;
      final label = TextPainter(
        text: TextSpan(
          text: items[i].name,
          style: TextStyle(
            color: labelColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(20.0, radius * slice * 0.85));
      final offset = Offset(
        center.dx + math.cos(middle) * labelRadius,
        center.dy + math.sin(middle) * labelRadius,
      );
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(middle + math.pi / 2);
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
    }
    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius * 0.13)),
      Colors.black26,
      3,
      true,
    );
    canvas.drawCircle(center, radius * 0.13, Paint()..color = centerColor);
    canvas.drawCircle(center, radius * 0.055, Paint()..color = accent);
    final pointer = Path()
      ..moveTo(center.dx - 12, center.dy - radius - 7)
      ..lineTo(center.dx + 12, center.dy - radius - 7)
      ..lineTo(center.dx, center.dy - radius + 19)
      ..close();
    canvas.drawShadow(pointer, Colors.black45, 3, true);
    canvas.drawPath(
      pointer,
      Paint()
        ..color = centerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(pointer, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.items != items ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.rotation != rotation ||
      oldDelegate.accent != accent ||
      oldDelegate.centerColor != centerColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.colors != colors;
}

class WheelPanel extends StatefulWidget {
  const WheelPanel({
    required this.session,
    required this.room,
    required this.enabled,
    required this.busy,
    required this.onAction,
    this.onManage,
    super.key,
  });

  final RoomSession session;
  final RoomState room;
  final bool enabled;
  final bool busy;
  final WheelAction onAction;
  final VoidCallback? onManage;

  @override
  State<WheelPanel> createState() => _WheelPanelState();
}

class _WheelPanelState extends State<WheelPanel> {
  bool _spinning = false;

  RoomSession get session => widget.session;
  RoomState get room => widget.room;
  bool get enabled => widget.enabled && !_spinning;
  bool get busy => widget.busy;
  WheelAction get onAction => widget.onAction;

  @override
  void didUpdateWidget(covariant WheelPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (room.wheel.spinId != oldWidget.room.wheel.spinId) {
      _spinning = room.wheel.spinId != null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wheel = room.wheel;
    final categoryCount = room.categories.length;
    final activityCount = room.categories.fold<int>(
      0,
      (sum, category) => sum + category.activities.length,
    );
    WheelCategory? selectedCategory;
    for (final category in room.categories) {
      if (category.id == wheel.selectedCategoryId) {
        selectedCategory = category;
        break;
      }
    }
    final activityReady = selectedCategory?.activities.isNotEmpty ?? false;
    final wheelItems = wheel.phase == 'activity' && selectedCategory != null
        ? selectedCategory.activities
              .map((activity) => (id: activity.id, name: activity.name))
              .toList()
        : room.categories
              .map((category) => (id: category.id, name: category.name))
              .toList();
    final selectedWheelId = wheel.phase == 'activity'
        ? wheel.selectedActivityId
        : wheel.selectedCategoryId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Two-stage wheel',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Choose a category, then spin again for an activity.'),
        if (wheelItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SizedBox.square(
              dimension: 280,
              child: _WheelGraphic(
                items: wheelItems,
                selectedId: selectedWheelId,
                spinId: wheel.spinId,
                animateOnMount: _spinning,
                onSpinComplete: () {
                  if (mounted) setState(() => _spinning = false);
                },
              ),
            ),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Waiting for the room update…'),
              ],
            ),
          ),
        if (_spinning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Spinning…', textAlign: TextAlign.center),
          ),
        if (!_spinning && wheel.phase != null && wheel.result != null) ...[
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Card(
              key: ValueKey(wheel.spinId),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      wheel.phase == 'category'
                          ? 'Category selected'
                          : 'Activity selected',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wheel.result!,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (wheel.phase == 'activity' && selectedCategory != null)
                      Text('In ${selectedCategory.name}'),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (room.categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No categories yet.'),
          ),
        Text(
          '$categoryCount ${categoryCount == 1 ? 'category' : 'categories'} · $activityCount ${activityCount == 1 ? 'activity' : 'activities'}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (room.isHost) ...[
          OutlinedButton.icon(
            onPressed: enabled ? widget.onManage : null,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Manage choices'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: enabled && room.categories.isNotEmpty
                ? () => onAction((api) => api.spinCategory(session))
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Spin category wheel'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: enabled && activityReady
                ? () => onAction((api) => api.spinActivity(session))
                : null,
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Spin activity wheel'),
          ),
          if (!_spinning && wheel.selectedCategoryId != null && !activityReady)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Add an activity to the selected category to spin.'),
            ),
        ] else if (room.categories.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('The host controls category and activity spins.'),
          ),
      ],
    );
  }
}
