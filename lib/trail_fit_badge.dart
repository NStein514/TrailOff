import 'package:flutter/material.dart';

import 'trail_catalogue.dart';

/// Shared badge for how well a route matches the current ability and
/// conditions.
class TrailFitBadge extends StatelessWidget {
  const TrailFitBadge({super.key, required this.fit});

  final TrailFit fit;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (fit) {
      TrailFit.comfortable => (
        const Color(0xFFE7F3EC),
        const Color(0xFF2F7154),
      ),
      TrailFit.stretch => (const Color(0xFFFBF1DF), const Color(0xFF8A5D1F)),
      TrailFit.tooDemanding => (
        const Color(0xFFF8EAE7),
        const Color(0xFF95493D),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        fit.label,
        style: TextStyle(
          color: foreground,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
