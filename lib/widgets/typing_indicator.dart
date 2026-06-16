import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    ));
    _animations = _controllers.map((c) => Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: c, curve: Curves.easeInOut),
    )).toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _animations[i],
        builder: (context, child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Transform.translate(
            offset: Offset(0, _animations[i].value),
            child: child,
          ),
        ),
        child: Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      )),
    );
  }
}
