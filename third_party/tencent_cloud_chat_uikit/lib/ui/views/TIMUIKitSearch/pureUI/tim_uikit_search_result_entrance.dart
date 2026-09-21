import 'package:flutter/material.dart';

class SearchResultEntrance extends StatefulWidget {
  static const Duration duration = Duration(milliseconds: 150);
  static const double offsetY = 8;

  const SearchResultEntrance({
    Key? key,
    required this.animate,
    required this.generation,
    required this.child,
  }) : super(key: key);

  final bool animate;
  final int generation;
  final Widget child;

  @override
  State<SearchResultEntrance> createState() => _SearchResultEntranceState();
}

class _SearchResultEntranceState extends State<SearchResultEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _translateY;
  int? _playedGeneration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SearchResultEntrance.duration,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _opacity = curve;
    _translateY = Tween<double>(
      begin: SearchResultEntrance.offsetY,
      end: 0,
    ).animate(curve);
    _startIfNeeded();
  }

  @override
  void didUpdateWidget(SearchResultEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _playedGeneration = null;
    }
    _startIfNeeded();
  }

  void _startIfNeeded() {
    if (!widget.animate) {
      if (_playedGeneration != widget.generation) {
        _controller.value = 1;
        _playedGeneration = widget.generation;
      }
      return;
    }
    if (_playedGeneration == widget.generation) {
      return;
    }
    _playedGeneration = widget.generation;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _translateY.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
