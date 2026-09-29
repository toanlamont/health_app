import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/metric_chart.dart';

const _mealTypes = {
  'breakfast': 'Bữa sáng',
  'lunch': 'Bữa trưa',
  'dinner': 'Bữa tối',
  'snack': 'Ăn vặt',
};

const _mealIcons = {
  'breakfast': Icons.free_breakfast,
  'lunch': Icons.lunch_dining,
  'dinner': Icons.dinner_dining,
  'snack': Icons.cookie,
};

class MealsScreen extends StatefulWidget {
  const MealsScreen({super.key});

  @override
  State<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends State<MealsScreen> {
  final _api = ApiClient();

  Map<String, dynamic>? _summary;
  List<dynamic> _meals = [];
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
        _api.dio.get('/nutrition/summary', queryParameters: {'days': 14}),
        _api.dio.get('/meals'),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = responses[0].data as Map<String, dynamic>;
        _meals = responses[1].data as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addMeal() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddMealSheet(),
    );
    if (added == true) _load();
  }

  Future<void> _deleteMeal(String id) async {
    try {
      await _api.dio.delete('/meals/$id');
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không xoá được, thử lại sau')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final target = _summary?['target'] as Map<String, dynamic>?;
    final eaten = (_summary?['calories'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMeal,
        backgroundColor: Metric.calories,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Thêm món'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text('Nhật ký ăn uống', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              DateFormat("EEEE, d 'tháng' M", 'vi').format(DateTime.now()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            SectionCard(
              title: 'Hôm nay',
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
                        style: theme.textTheme.displaySmall
                            ?.copyWith(color: Metric.calories),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        target == null
                            ? 'kcal'
                            : '/ ${target['calories']} kcal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (target == null)
                    _MissingProfileNote()
                  else ...[
                    TargetBar(
                      used: eaten,
                      target: (target['calories'] as num).toDouble(),
                      colour: Metric.calories,
                    ),
                    const SizedBox(height: 16),
                    _MacroRow(summary: _summary!, target: target),
                    const SizedBox(height: 12),
                    Text(
                      'Mục tiêu tính theo công thức Mifflin-St Jeor từ '
                      '${target['from_weight_kg']} kg, ${target['from_height_cm']} cm, '
                      '${target['from_age']} tuổi. Đây là ước lượng, có thể lệch '
                      'vài trăm kcal tuỳ người.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            SectionCard(
              title: 'Calo 14 ngày qua',
              icon: Icons.show_chart,
              colour: Metric.calories,
              child: MetricChart(
                points: [
                  for (final day in (_summary?['history'] as List<dynamic>? ?? []))
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

            const SizedBox(height: 16),
            SectionCard(
              title: 'Các món đã ăn hôm nay',
              icon: Icons.restaurant_menu,
              colour: Metric.calories,
              trailing: Text(
                '${_meals.length} món',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              child: _meals.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Chưa ghi món nào hôm nay',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final meal in _meals)
                          _MealTile(
                            meal: meal as Map<String, dynamic>,
                            onDelete: () => _deleteMeal(meal['id'] as String),
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

class _MissingProfileNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Metric.goal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Metric.goal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Điền chiều cao, cân nặng và ngày sinh trong hồ sơ để tính '
              'được mục tiêu calo hằng ngày.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({required this.summary, required this.target});

  final Map<String, dynamic> summary;
  final Map<String, dynamic> target;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final macro in const [
          ('protein_g', 'Đạm', Metric.heart),
          ('carbs_g', 'Tinh bột', Metric.calories),
          ('fat_g', 'Chất béo', Metric.reminder),
        ])
          Expanded(
            child: _MacroPill(
              label: macro.$2,
              eaten: (summary[macro.$1] as num?)?.toDouble() ?? 0,
              target: (target[macro.$1] as num?)?.toDouble() ?? 0,
              colour: macro.$3,
            ),
          ),
      ],
    );
  }
}

class _MacroPill extends StatelessWidget {
  const _MacroPill({
    required this.label,
    required this.eaten,
    required this.target,
    required this.colour,
  });

  final String label;
  final double eaten;
  final double target;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${eaten.round()}/${target.round()}g',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colour,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: target <= 0 ? 0 : (eaten / target).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: colour.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealTile extends StatelessWidget {
  const _MealTile({required this.meal, required this.onDelete});

  final Map<String, dynamic> meal;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = meal['meal_type'] as String? ?? 'snack';
    final at = DateTime.parse(meal['eaten_at'] as String);

    return Dismissible(
      key: ValueKey(meal['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Metric.heart.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Metric.heart),
      ),
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Metric.calories.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _mealIcons[type] ?? Icons.restaurant,
                size: 18,
                color: Metric.calories,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal['name'] as String,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_mealTypes[type] ?? type} · ${DateFormat('HH:mm').format(at)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${meal['calories']} kcal',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Metric.calories,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMealSheet extends StatefulWidget {
  const _AddMealSheet();

  @override
  State<_AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends State<_AddMealSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  String _type = 'snack';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = _typeForNow();
  }

  /// Whichever meal it most likely is at this hour, so the common case needs
  /// no tapping.
  static String _typeForNow() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'breakfast';
    if (hour < 14) return 'lunch';
    if (hour >= 17 && hour < 22) return 'dinner';
    return 'snack';
  }

  @override
  void dispose() {
    _name.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  double? _optional(TextEditingController field) {
    final text = field.text.trim().replaceAll(',', '.');
    return text.isEmpty ? null : double.tryParse(text);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiClient().dio.post('/meals', data: {
        'name': _name.text.trim(),
        'calories': int.parse(_calories.text.trim()),
        'meal_type': _type,
        'protein_g': _optional(_protein),
        'carbs_g': _optional(_carbs),
        'fat_g': _optional(_fat),
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
            Text('Thêm món ăn', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              children: [
                for (final entry in _mealTypes.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _type == entry.key,
                    onSelected: (_) => setState(() => _type = entry.key),
                    selectedColor: Metric.calories.withValues(alpha: 0.2),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Tên món',
                hintText: 'Phở bò, cơm rang...',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập tên món' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _calories,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Calo',
                suffixText: 'kcal',
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null) return 'Nhập số calo';
                if (n <= 0 || n > 10000) return 'Số calo không hợp lý';
                return null;
              },
            ),
            const SizedBox(height: 12),

            Text(
              'Không bắt buộc',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _MacroField(controller: _protein, label: 'Đạm')),
                const SizedBox(width: 8),
                Expanded(child: _MacroField(controller: _carbs, label: 'Tinh bột')),
                const SizedBox(width: 8),
                Expanded(child: _MacroField(controller: _fat, label: 'Béo')),
              ],
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: Metric.calories),
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

class _MacroField extends StatelessWidget {
  const _MacroField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: 'g'),
    );
  }
}
