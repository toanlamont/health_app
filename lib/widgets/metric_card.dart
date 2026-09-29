import 'package:flutter/material.dart';

import '../app/theme.dart';

/// A single reading, in the colour that belongs to that measurement.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.colour,
    this.unit = '',
    this.footnote,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color colour;
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: Metric.wash(colour, theme.brightness),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: colour),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: colour,
                        height: 1.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colour.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
              if (footnote != null) ...[
                const SizedBox(height: 6),
                Text(
                  footnote!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled block with a chart or a list inside it.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.colour,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Color? colour;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = colour ?? theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: tint),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// The bar that shows how much of a daily target has been used.
class TargetBar extends StatelessWidget {
  const TargetBar({
    super.key,
    required this.used,
    required this.target,
    required this.colour,
  });

  final double used;
  final double target;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = target <= 0 ? 0.0 : (used / target);
    final over = ratio > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: colour.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(over ? Metric.heart : colour),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          over
              ? 'Vượt ${(used - target).round()} kcal so với mục tiêu'
              : 'Còn lại ${(target - used).round()} kcal',
          style: theme.textTheme.bodySmall?.copyWith(
            color: over ? Metric.heart : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
