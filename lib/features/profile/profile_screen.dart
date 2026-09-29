import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api_client.dart';
import '../../widgets/metric_card.dart';
import '../auth/auth_bloc.dart';
import '../goals/goals_screen.dart';
import '../history/history_screen.dart';
import '../reminders/reminders_screen.dart';

const _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiClient();
  final _height = TextEditingController();
  final _weight = TextEditingController();

  Map<String, dynamic>? _user;
  double? _bmi;
  String? _bloodType;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final responses = await Future.wait([
        _api.dio.get('/health-profile'),
        _api.dio.get('/auth/me'),
      ]);
      final profile = responses[0].data as Map<String, dynamic>;
      _height.text = profile['height_cm']?.toString() ?? '';
      _weight.text = profile['weight_kg']?.toString() ?? '';
      _bmi = (profile['bmi'] as num?)?.toDouble();
      _bloodType = profile['blood_type'] as String?;
      _user = responses[1].data as Map<String, dynamic>;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final height = double.tryParse(_height.text.trim().replaceAll(',', '.'));
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    try {
      final response = await _api.dio.put('/health-profile', data: {
        'height_cm': ?height,
        'weight_kg': ?weight,
        'blood_type': ?_bloodType,
      });
      if (!mounted) return;
      setState(() {
        _bmi = (response.data['bmi'] as num?)?.toDouble();
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu hồ sơ')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lưu được, kiểm tra kết nối')),
      );
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn sẽ cần đăng nhập lại để xem dữ liệu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Metric.heart),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<AuthBloc>().add(AuthLogout());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final name = (_user?['full_name'] as String?)?.trim();
    final email = _user?['email'] as String?;
    final born = _user?['date_of_birth'] as String?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('Hồ sơ', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: Metric.wash(Metric.goal, theme.brightness),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Metric.goal.withValues(alpha: 0.2),
                child: Text(
                  (name?.isNotEmpty == true ? name![0] : '?').toUpperCase(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Metric.goal,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name?.isNotEmpty == true ? name! : 'Chưa đặt tên',
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email != null)
                      Text(
                        email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (born != null)
                      Text(
                        'Sinh ${DateFormat('dd/MM/yyyy').format(DateTime.parse(born))}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        SectionCard(
          title: 'Chỉ số cơ thể',
          icon: Icons.straighten,
          colour: Metric.weight,
          child: Column(
            children: [
              if (_bmi != null) ...[
                Row(
                  children: [
                    Text('BMI', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text(
                      _bmi!.toStringAsFixed(1),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Metric.weight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _bmiLabel(_bmi!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _height,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Chiều cao',
                        suffixText: 'cm',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cân nặng',
                        suffixText: 'kg',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _bloodType,
                decoration: const InputDecoration(labelText: 'Nhóm máu'),
                items: [
                  for (final type in _bloodTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (v) => setState(() => _bloodType = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Metric.goal,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Lưu hồ sơ'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Chiều cao, cân nặng và ngày sinh dùng để tính mục tiêu calo '
                'hằng ngày.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _NavTile(
          icon: Icons.flag,
          colour: Metric.goal,
          title: 'Mục tiêu',
          subtitle: 'Đặt và theo dõi mục tiêu sức khoẻ',
          onTap: () => _open(const GoalsScreen()),
        ),
        _NavTile(
          icon: Icons.notifications,
          colour: Metric.reminder,
          title: 'Nhắc nhở',
          subtitle: 'Uống nước, đo nhịp tim, ghi bữa ăn',
          onTap: () => _open(const RemindersScreen()),
        ),
        _NavTile(
          icon: Icons.history,
          colour: Metric.heart,
          title: 'Lịch sử đo',
          subtitle: 'Toàn bộ các lần đo nhịp tim',
          onTap: () => _open(const HistoryScreen()),
        ),

        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Metric.heart,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  static String _bmiLabel(double bmi) {
    if (bmi < 18.5) return 'Thiếu cân';
    if (bmi < 25) return 'Bình thường';
    if (bmi < 30) return 'Thừa cân';
    return 'Béo phì';
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.colour,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: colour),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}
