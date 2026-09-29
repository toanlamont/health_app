import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/metric_chart.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiClient();
  List<dynamic> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await _api.dio.get(
        '/heart-rate',
        queryParameters: {'limit': 100},
      );
      if (!mounted) return;
      setState(() {
        _records = response.data as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử đo')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _records.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 60),
                        Icon(
                          Icons.monitor_heart_outlined,
                          size: 56,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Chưa có lần đo nào',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        SectionCard(
                          title: 'Diễn biến nhịp tim',
                          icon: Icons.show_chart,
                          colour: Metric.heart,
                          child: MetricChart(
                            points: [
                              for (final record in _records)
                                MetricPoint(
                                  DateTime.parse(
                                    record['measured_at'] as String,
                                  ),
                                  (record['bpm'] as num).toDouble(),
                                ),
                            ],
                            colour: Metric.heart,
                            unit: ' bpm',
                            height: 220,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${_records.length} lần đo',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        for (final record in _records)
                          _HeartRateTile(record: record as Map<String, dynamic>),
                      ],
                    ),
            ),
    );
  }
}

class _HeartRateTile extends StatelessWidget {
  const _HeartRateTile({required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bpm = record['bpm'] as int;
    final zone = _zone(bpm);
    final at = DateTime.parse(record['measured_at'] as String);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: zone.$2.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.favorite, size: 18, color: zone.$2),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$bpm',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: zone.$2,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'bpm',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Text(
          DateFormat('dd/MM/yyyy HH:mm').format(at),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: zone.$2.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            zone.$1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: zone.$2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  static (String, Color) _zone(int bpm) {
    if (bpm < 60) return ('Chậm', Metric.reminder);
    if (bpm <= 100) return ('Bình thường', Metric.goal);
    if (bpm <= 120) return ('Hơi nhanh', Metric.calories);
    return ('Nhanh', Metric.heart);
  }
}
