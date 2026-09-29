import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One point on a chart: when it was recorded and what was recorded.
class MetricPoint {
  const MetricPoint(this.at, this.value);
  final DateTime at;
  final double value;
}

/// A line chart with both axes labelled.
///
/// The dashboard used to draw a bare line with no scale on it, which cannot
/// answer the only questions worth asking of a chart: how much, and when. This
/// one carries a value axis on the left, dates along the bottom, gridlines to
/// read against, and a tooltip on touch. An optional [target] draws a dashed
/// reference line, for a calorie goal or a resting-rate band.
class MetricChart extends StatelessWidget {
  const MetricChart({
    super.key,
    required this.points,
    required this.colour,
    this.unit = '',
    this.target,
    this.targetLabel,
    this.height = 200,
    this.decimals = 0,
  });

  final List<MetricPoint> points;
  final Color colour;
  final String unit;
  final double? target;
  final String? targetLabel;
  final double height;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'Chưa có dữ liệu'
                : 'Cần ít nhất hai lần ghi để vẽ biểu đồ',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final sorted = [...points]..sort((a, b) => a.at.compareTo(b.at));
    final values = sorted.map((p) => p.value).toList();
    var lowest = values.reduce((a, b) => a < b ? a : b);
    var highest = values.reduce((a, b) => a > b ? a : b);
    if (target != null) {
      lowest = lowest < target! ? lowest : target!;
      highest = highest > target! ? highest : target!;
    }

    // A flat series would otherwise collapse to a zero-height axis and the
    // line would sit on the frame.
    final span = (highest - lowest).abs() < 1e-9 ? highest.abs() * 0.2 + 1 : highest - lowest;
    final padding = span * 0.15;
    final minY = lowest - padding;
    final maxY = highest + padding;
    final step = _niceStep((maxY - minY) / 4);

    final first = sorted.first.at.millisecondsSinceEpoch.toDouble();
    final last = sorted.last.at.millisecondsSinceEpoch.toDouble();
    final sameDay = sorted.last.at.difference(sorted.first.at).inHours < 24;
    final labels = DateFormat(sameDay ? 'HH:mm' : 'dd/MM');

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: first,
          maxX: last,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
              dashArray: const [4, 4],
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(color: theme.colorScheme.outlineVariant),
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: step,
                getTitlesWidget: (value, meta) {
                  // The axis ends carry the frame already; repeating them as
                  // numbers crowds the corner.
                  if (value <= minY + step * 0.1 || value >= maxY - step * 0.1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      value.toStringAsFixed(decimals),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: ((last - first) / 3).clamp(1, double.infinity),
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels.format(
                      DateTime.fromMillisecondsSinceEpoch(value.toInt()),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
          extraLinesData: target == null
              ? const ExtraLinesData()
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: target!,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      strokeWidth: 1.5,
                      dashArray: const [6, 4],
                      label: HorizontalLineLabel(
                        show: targetLabel != null,
                        alignment: Alignment.topRight,
                        labelResolver: (_) => targetLabel ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItems: (spots) => spots.map((spot) {
                final at = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(decimals)}$unit\n'
                  '${DateFormat('dd/MM HH:mm').format(at)}',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final p in sorted)
                  FlSpot(p.at.millisecondsSinceEpoch.toDouble(), p.value),
              ],
              isCurved: true,
              curveSmoothness: 0.25,
              // Without this a curve through closely spaced points can bulge
              // past them and show a value that was never recorded.
              preventCurveOverShooting: true,
              color: colour,
              barWidth: 3,
              dotData: FlDotData(
                show: sorted.length <= 15,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 3.5,
                  color: colour,
                  strokeWidth: 2,
                  strokeColor: theme.colorScheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colour.withValues(alpha: 0.28),
                    colour.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A gridline spacing a person would pick: 1, 2, 5, 10, 20, 50 and so on.
  static double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 1;
    var scale = 1.0;
    var value = raw;
    while (value >= 10) {
      value /= 10;
      scale *= 10;
    }
    while (value < 1) {
      value *= 10;
      scale /= 10;
    }
    final rounded = value <= 1 ? 1.0 : (value <= 2 ? 2.0 : (value <= 5 ? 5.0 : 10.0));
    return rounded * scale;
  }
}
