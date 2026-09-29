import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';

/// Ready-made reminders, so the common cases need no typing. The schedule is
/// stored as cron because that is what the API takes.
const _presets = [
  ('water', 'Uống nước', '0 */2 8-22 * * *', 'Hai tiếng một lần, 8h đến 22h', Icons.water_drop),
  ('measure', 'Đo nhịp tim', '0 0 9,21 * * *', 'Mỗi ngày 9h và 21h', Icons.favorite),
  ('meal', 'Ghi bữa ăn', '0 0 12,19 * * *', 'Mỗi ngày 12h và 19h', Icons.restaurant),
  ('weight', 'Cân', '0 0 7 * * 1', 'Sáng thứ hai hằng tuần', Icons.monitor_weight),
];

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _api = ApiClient();
  List<dynamic> _reminders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await _api.dio.get('/reminders');
      if (!mounted) return;
      setState(() {
        _reminders = response.data as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _add(String type, String title, String cron) async {
    try {
      await _api.dio.post('/reminders', data: {
        'type': type,
        'title': title,
        'schedule_cron': cron,
      });
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thêm được, kiểm tra kết nối')),
      );
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _api.dio.delete('/reminders/$id');
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không xoá được')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = {for (final r in _reminders) r['type'] as String};

    return Scaffold(
      appBar: AppBar(title: const Text('Nhắc nhở')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Metric.reminder.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Metric.reminder,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Nhắc nhở được lưu trên máy chủ. Thông báo đẩy về '
                            'điện thoại chưa làm, nên hiện tại đây là danh sách '
                            'lịch chứ chưa rung chuông.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_reminders.isNotEmpty) ...[
                    Text('Đang bật', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 10),
                    for (final reminder in _reminders)
                      _ReminderTile(
                        reminder: reminder as Map<String, dynamic>,
                        onDelete: () => _delete(reminder['id'] as String),
                      ),
                    const SizedBox(height: 24),
                  ],

                  Text('Thêm nhanh', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  for (final preset in _presets)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Metric.reminder.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            preset.$5,
                            size: 18,
                            color: Metric.reminder,
                          ),
                        ),
                        title: Text(
                          preset.$2,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          preset.$4,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: existing.contains(preset.$1)
                            ? const Icon(
                                Icons.check_circle,
                                color: Metric.goal,
                                size: 20,
                              )
                            : IconButton(
                                onPressed: () =>
                                    _add(preset.$1, preset.$2, preset.$3),
                                icon: const Icon(Icons.add_circle_outline),
                                color: Metric.reminder,
                              ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.onDelete});

  final Map<String, dynamic> reminder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _presets.where((p) => p.$1 == reminder['type']).firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: const BoxDecoration(
            color: Color(0x223E63DD),
            shape: BoxShape.circle,
          ),
          child: Icon(
            preset?.$5 ?? Icons.alarm,
            size: 18,
            color: Metric.reminder,
          ),
        ),
        title: Text(
          reminder['title'] as String,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          preset?.$4 ?? reminder['schedule_cron'] as String,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          color: Metric.heart,
        ),
      ),
    );
  }
}
