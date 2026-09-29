import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../widgets/metric_card.dart';

/// The goals someone can set, with the unit and icon that go with each.
const _goalTypes = {
  'weight': ('Cân nặng mục tiêu', 'kg', Icons.monitor_weight, Metric.weight),
  'heart_rate': ('Nhịp tim nghỉ', 'bpm', Icons.favorite, Metric.heart),
  'calories': ('Calo mỗi ngày', 'kcal', Icons.local_fire_department, Metric.calories),
  'measurements': ('Số lần đo mỗi tuần', 'lần', Icons.timeline, Metric.goal),
};

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _api = ApiClient();
  List<dynamic> _goals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await _api.dio.get('/goals');
      if (!mounted) return;
      setState(() {
        _goals = response.data as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _addGoal() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddGoalSheet(),
    );
    if (added == true) _load();
  }

  Future<void> _updateProgress(Map<String, dynamic> goal) async {
    final controller = TextEditingController(
      text: (goal['current_value'] as num).toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cập nhật tiến độ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Giá trị hiện tại',
            suffixText: goal['unit'] as String,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(controller.text.trim().replaceAll(',', '.')),
            ),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await _api.dio.put('/goals/${goal['id']}', data: {'current_value': value});
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không cập nhật được')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mục tiêu')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGoal,
        backgroundColor: Metric.goal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Thêm mục tiêu'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _goals.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 60),
                        Icon(
                          Icons.flag_outlined,
                          size: 56,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Chưa có mục tiêu nào',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Đặt một mục tiêu để theo dõi tiến độ theo thời gian.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _goals.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _GoalCard(
                        goal: _goals[index] as Map<String, dynamic>,
                        onTap: () => _updateProgress(
                          _goals[index] as Map<String, dynamic>,
                        ),
                      ),
                    ),
            ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onTap});

  final Map<String, dynamic> goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = goal['type'] as String;
    final meta = _goalTypes[type];
    final colour = meta?.$4 ?? Metric.goal;
    final target = (goal['target_value'] as num).toDouble();
    final current = (goal['current_value'] as num).toDouble();
    final deadline = goal['deadline'] as String?;

    // Progress towards a weight goal usually means coming down to it, so a
    // plain current/target would read backwards.
    final ratio = target <= 0 ? 0.0 : (current / target).clamp(0.0, 1.0);

    return SectionCard(
      title: meta?.$1 ?? type,
      icon: meta?.$3 ?? Icons.flag,
      colour: colour,
      trailing: IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.edit_outlined, size: 18),
        tooltip: 'Cập nhật tiến độ',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                current.toStringAsFixed(current % 1 == 0 ? 0 : 1),
                style: theme.textTheme.displaySmall?.copyWith(color: colour),
              ),
              const SizedBox(width: 6),
              Text(
                '/ ${target.toStringAsFixed(target % 1 == 0 ? 0 : 1)} ${goal['unit']}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: colour.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
          if (deadline != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.event,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Hạn ${DateFormat('dd/MM/yyyy').format(DateTime.parse(deadline))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AddGoalSheet extends StatefulWidget {
  const _AddGoalSheet();

  @override
  State<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<_AddGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _target = TextEditingController();
  String _type = 'weight';
  DateTime? _deadline;
  bool _saving = false;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiClient().dio.post('/goals', data: {
        'type': _type,
        'target_value': double.parse(_target.text.trim().replaceAll(',', '.')),
        'unit': _goalTypes[_type]!.$2,
        if (_deadline != null)
          'deadline': DateFormat('yyyy-MM-dd').format(_deadline!),
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
    final meta = _goalTypes[_type]!;

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
            Text('Thêm mục tiêu', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _goalTypes.entries)
                  ChoiceChip(
                    avatar: Icon(entry.value.$3, size: 16),
                    label: Text(entry.value.$1),
                    selected: _type == entry.key,
                    onSelected: (_) => setState(() => _type = entry.key),
                    selectedColor: entry.value.$4.withValues(alpha: 0.2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _target,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Giá trị mục tiêu',
                suffixText: meta.$2,
              ),
              validator: (v) {
                final n = double.tryParse(
                  (v ?? '').trim().replaceAll(',', '.'),
                );
                if (n == null || n <= 0) return 'Nhập giá trị mục tiêu';
                return null;
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: now.add(const Duration(days: 30)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365 * 3)),
                );
                if (picked != null) setState(() => _deadline = picked);
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text(
                _deadline == null
                    ? 'Đặt hạn (không bắt buộc)'
                    : 'Hạn ${DateFormat('dd/MM/yyyy').format(_deadline!)}',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: meta.$4),
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
