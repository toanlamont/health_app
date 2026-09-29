import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/metric_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onGoToTab});

  /// Lets a card send the user to the tab that owns that measurement.
  final void Function(int index)? onGoToTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiClient();

  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _nutrition;
  Map<String, dynamic>? _user;
  List<dynamic> _heartRates = [];
  List<dynamic> _weights = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetched together: one slow endpoint should not hold up the rest.
      final responses = await Future.wait([
        _api.dio.get('/dashboard'),
        _api.dio.get('/heart-rate', queryParameters: {'limit': 30}),
        _api.dio.get('/nutrition/summary', queryParameters: {'days': 14}),
        _api.dio.get('/weight', queryParameters: {'limit': 30}),
        _api.dio.get('/auth/me'),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = responses[0].data as Map<String, dynamic>;
        _heartRates = responses[1].data as List<dynamic>;
        _nutrition = responses[2].data as Map<String, dynamic>;
        _weights = responses[3].data as List<dynamic>;
        _user = responses[4].data as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không tải được dữ liệu. Kiểm tra kết nối tới máy chủ.';
      });
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Chào buổi sáng';
    if (hour < 14) return 'Chào buổi trưa';
    if (hour < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final name = (_user?["full_name"] as String?)?.trim();
    final target = _nutrition?['target'] as Map<String, dynamic>?;
    final eaten = (_nutrition?['calories'] as num?)?.toDouble() ?? 0;
    final latestBpm = _dashboard?['latest_bpm'] as int?;
    final avgBpm = (_dashboard?['avg_bpm_7d'] as num?)?.toDouble();
    final bmi = (_dashboard?['current_bmi'] as num?)?.toDouble();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            _greeting(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name == null || name.isEmpty ? 'Hôm nay thế nào?' : name,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat("EEEE, d 'tháng' M", 'vi').format(DateTime.now()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Metric.heart.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Metric.heart, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: MetricCard(
                  icon: Icons.favorite,
                  label: 'Nhịp tim',
                  value: latestBpm?.toString() ?? '--',
                  unit: 'bpm',
                  colour: Metric.heart,
                  footnote: avgBpm == null
                      ? 'Chưa đo lần nào'
                      : 'TB 7 ngày ${avgBpm.toStringAsFixed(0)}',
                  onTap: () => widget.onGoToTab?.call(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  icon: Icons.local_fire_department,
                  label: 'Calo hôm nay',
                  value: eaten.round().toString(),
                  unit: 'kcal',
                  colour: Metric.calories,
                  footnote: target == null
                      ? 'Chưa đủ hồ sơ để tính'
                      : 'Mục tiêu ${target['calories']}',
                  onTap: () => widget.onGoToTab?.call(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  icon: Icons.monitor_weight,
                  label: 'Cân nặng',
                  value: _weights.isEmpty
                      ? '--'
                      : (_weights.first['weight_kg'] as num).toStringAsFixed(1),
                  unit: 'kg',
                  colour: Metric.weight,
                  footnote: bmi == null
                      ? 'Chưa có BMI'
                      : 'BMI ${bmi.toStringAsFixed(1)} · ${_bmiLabel(bmi)}',
                  onTap: () => widget.onGoToTab?.call(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  icon: Icons.flag,
                  label: 'Mục tiêu',
                  value: (_dashboard?['active_goals'] ?? 0).toString(),
                  unit: 'đang theo',
                  colour: Metric.goal,
                  footnote: '${_dashboard?['measurement_count'] ?? 0} lần đo',
                  onTap: () => widget.onGoToTab?.call(4),
                ),
              ),
            ],
          ),

          if (target != null) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Năng lượng hôm nay',
              icon: Icons.local_fire_department,
              colour: Metric.calories,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        eaten.round().toString(),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Metric.calories,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ ${target['calories']} kcal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TargetBar(
                    used: eaten,
                    target: (target['calories'] as num).toDouble(),
                    colour: Metric.calories,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          SectionCard(
            title: 'Nhịp tim 30 lần đo gần nhất',
            icon: Icons.show_chart,
            colour: Metric.heart,
            child: MetricChart(
              points: [
                for (final record in _heartRates)
                  MetricPoint(
                    DateTime.parse(record['measured_at'] as String),
                    (record['bpm'] as num).toDouble(),
                  ),
              ],
              colour: Metric.heart,
              unit: ' bpm',
            ),
          ),

          const SizedBox(height: 16),
          SectionCard(
            title: 'Calo 14 ngày qua',
            icon: Icons.local_fire_department,
            colour: Metric.calories,
            child: MetricChart(
              points: [
                for (final day in (_nutrition?['history'] as List<dynamic>? ?? []))
                  MetricPoint(
                    DateTime.parse(day['day'] as String),
                    (day['calories'] as num).toDouble(),
                  ),
              ],
              colour: Metric.calories,
              unit: ' kcal',
              target: (target?['calories'] as num?)?.toDouble(),
              targetLabel: target == null ? null : 'Mục tiêu',
            ),
          ),

          if (_weights.length >= 2) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Cân nặng theo thời gian',
              icon: Icons.monitor_weight,
              colour: Metric.weight,
              child: MetricChart(
                points: [
                  for (final record in _weights)
                    MetricPoint(
                      DateTime.parse(record['recorded_at'] as String),
                      (record['weight_kg'] as num).toDouble(),
                    ),
                ],
                colour: Metric.weight,
                unit: ' kg',
                decimals: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _bmiLabel(double bmi) {
    // The WHO cut-offs.
    if (bmi < 18.5) return 'Thiếu cân';
    if (bmi < 25) return 'Bình thường';
    if (bmi < 30) return 'Thừa cân';
    return 'Béo phì';
  }
}
