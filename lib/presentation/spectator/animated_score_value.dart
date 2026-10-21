import 'package:flutter/material.dart';

class AnimatedScoreValue extends StatefulWidget {
  const AnimatedScoreValue({required this.points, super.key});
  final int points;

  @override
  State<AnimatedScoreValue> createState() => _AnimatedScoreValueState();
}

class _AnimatedScoreValueState extends State<AnimatedScoreValue>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late double _from = widget.points.toDouble();
  int _gain = 0;

  double get _value =>
      _from +
      (widget.points - _from) *
          Curves.easeOutCubic.transform(_controller.value);

  @override
  void didUpdateWidget(AnimatedScoreValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points == widget.points) return;
    final previous = _controller.isAnimating
        ? _from +
              (oldWidget.points - _from) *
                  Curves.easeOutCubic.transform(_controller.value)
        : oldWidget.points.toDouble();
    _from = previous;
    _gain = widget.points - oldWidget.points;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final progress = _controller.value;
      final glow = _gain > 0 ? (1 - progress) : 0.0;
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: 1 + glow * .18,
            child: Text(
              '${_controller.isAnimating ? _value.round() : widget.points}',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: glow > .1 ? Colors.amber : null,
                shadows: [
                  Shadow(
                    color: Colors.amber.withValues(alpha: glow),
                    blurRadius: 24 * glow,
                  ),
                ],
              ),
            ),
          ),
          if (_gain > 0 && _controller.isAnimating)
            Positioned(
              top: -12 - 28 * progress,
              child: Opacity(
                opacity: (1 - progress).clamp(0, 1),
                child: Text(
                  '✦ +$_gain',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.amber,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
