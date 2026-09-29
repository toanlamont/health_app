import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/metric_chart.dart';

/// WHO cut-offs, with the colour each band is drawn in.
const _bmiBands = [
  (0.0, 18.5, 'Thiếu cân', Metric.reminder),
  (18.5, 25.0, 'Bình thường', Metric.goal),
  (25.0, 30.0, 'Thừa cân', Metric.calories),
  (30.0, 999.0, 'Béo phì', Metric.heart),
];

(String, Color) bmiBand(double bmi) {
  for (final band in _bmiBands) {
    if (bmi >= band.$1 && bmi < band.$2) return (band.$3, band.$4);
  }
  return ('Không rõ', Metric.weight);
}

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  final _api = ApiClient();

  List<dynamic> _records = [];
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final responses = await Future.wait([
        _api.dio.get('/weight', queryParameters: {'limit': 60}),
        _api.dio.get('/health-profile'),
      ]);
      if (!mounted) return;
      setState(() {
        _records = responses[0].data as List<dynamic>;
        _profile = responses[1].data as Map<String, dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addWeight() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddWeightSheet(
        last: _records.isEmpty
            ? null
            : (_records.first['weight_kg'] as num).toDouble(),
      ),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final height = (_profile?['height_cm'] as num?)?.toDouble();
    final latest = _records.isEmpty
        ? null
        : (_records.first['weight_kg'] as num).toDouble();
    final bmi = (_profile?['bmi'] as num?)?.toDouble();

    // Change since the oldest reading held, which is what someone tracking
    // weight actually wants to see.
    double? change;
    if (_records.length >= 2) {
      final oldest = (_records.last['weight_kg'] as num).toDouble();
      change = latest! - oldest;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWeight,
        backgroundColor: Metric.weight,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Ghi cân nặng'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text('Cân nặng', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    icon: Icons.monitor_weight,
                    label: 'Hiện tại',
                    value: latest?.toStringAsFixed(1) ?? '--',
                    unit: 'kg',
                    colour: Metric.weight,
                    footnote: change == null
                        ? '${_records.length} lần ghi'
                        : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} kg từ lần đầu',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    icon: Icons.straighten,
                    label: 'BMI',
                    value: bmi?.toStringAsFixed(1) ?? '--',
                    unit: '',
                    colour: bmi == null ? Metric.weight : bmiBand(bmi).$2,
                    footnote: bmi == null
                        ? (height == null ? 'Cần chiều cao' : 'Chưa có cân nặng')
                        : bmiBand(bmi).$1,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            SectionCard(
              title: 'Diễn biến cân nặng',
              icon: Icons.show_chart,
              colour: Metric.weight,
              child: MetricChart(
                points: [
                  for (final record in _records)
                    MetricPoint(
                      DateTime.parse(record['recorded_at'] as String),
                      (record['weight_kg'] as num).toDouble(),
                    ),
                ],
                colour: Metric.weight,
                unit: ' kg',
                decimals: 1,
                height: 220,
              ),
            ),

            if (bmi != null) ...[
              const SizedBox(height: 16),
              SectionCard(
                title: 'Phân loại BMI',
                icon: Icons.straighten,
                colour: bmiBand(bmi).$2,
                child: _BmiScale(bmi: bmi),
              ),
            ],

            const SizedBox(height: 16),
            SectionCard(
              title: 'Lịch sử',
              icon: Icons.history,
              colour: Metric.weight,
              child: _records.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Chưa ghi lần nào',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final record in _records.take(12))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    DateFormat('dd/MM/yyyy HH:mm').format(
                                      DateTime.parse(
                                        record['recorded_at'] as String,
                                      ),
                                    ),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(record['weight_kg'] as num).toStringAsFixed(1)} kg',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Metric.weight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BmiScale extends StatelessWidget {
  const _BmiScale({required this.bmi});

  final double bmi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The scale is drawn from 15 to 35, where nearly every reading falls.
    const low = 15.0;
    const high = 35.0;
    final position = ((bmi - low) / (high - low)).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: 44,
              child: Stack(
                children: [
                  Positioned(
                    top: 18,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Row(
                        children: [
                          for (final band in _bmiBands)
                            Expanded(
                              flex: (((band.$2 > high ? high : band.$2) -
                                          (band.$1 < low ? low : band.$1)) *
                                      10)
                                  .round()
                                  .clamp(1, 10000),
                              child: Container(height: 10, color: band.$4),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (position * width - 9).clamp(0.0, width - 18),
                    top: 12,
                    child: Container(
                      width: 18,
                      height: 22,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: bmiBand(bmi).$2, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in ['15', '18.5', '25', '30', '35'])
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'BMI ${bmi.toStringAsFixed(1)} — ${bmiBand(bmi).$1}. Chỉ số này không '
          'phân biệt cơ và mỡ, nên với người tập nặng nó có thể cao mà không '
          'phản ánh đúng.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AddWeightSheet extends StatefulWidget {
  const _AddWeightSheet({this.last});

  final double? last;

  @override
  State<_AddWeightSheet> createState() => _AddWeightSheetState();
}

class _AddWeightSheetState extends State<_AddWeightSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weight;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Prefilled with the last reading: most entries are a small change from it.
    _weight = TextEditingController(text: widget.last?.toStringAsFixed(1) ?? '');
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiClient().dio.post('/weight', data: {
        'weight_kg': double.parse(_weight.text.trim().replaceAll(',', '.')),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lưu được, kiểm tra kết nối')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ghi cân nặng', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextFormField(
              controller: _weight,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cân nặng',
                suffixText: 'kg',
              ),
              validator: (v) {
                final n = double.tryParse(
                  (v ?? '').trim().replaceAll(',', '.'),
                );
                if (n == null) return 'Nhập cân nặng';
                if (n < 20 || n > 400) return 'Cân nặng không hợp lý';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: Metric.weight),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Lưu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
