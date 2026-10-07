import 'package:flutter/material.dart';

import '../features/chat/chat_head.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/heart_rate/measure_screen.dart';
import '../features/nutrition/meals_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/weight/weight_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Kept alive between tabs so switching away and back does not refetch and
  // lose scroll position.
  late final List<Widget> _screens = [
    DashboardScreen(onGoToTab: _select),
    const MeasureScreen(),
    const WeightScreen(),
    const ProfileScreen(),
  ];

  // The calorie target is worked out from the profile, which is edited on
  // another tab, so this screen is rebuilt each time it is opened.
  int _mealsVersion = 0;

  void _select(int i) => setState(() {
    if (i == 2 && _index != 2) _mealsVersion++;
    _index = i;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ChatHead(
          child: IndexedStack(
            index: _index,
            children: [
              _screens[0],
              _screens[1],
              MealsScreen(key: ValueKey(_mealsVersion)),
              _screens[2],
              _screens[3],
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Đo',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Calo',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_weight_outlined),
            selectedIcon: Icon(Icons.monitor_weight),
            label: 'Cân nặng',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Hồ sơ',
          ),
        ],
      ),
    );
  }
}
