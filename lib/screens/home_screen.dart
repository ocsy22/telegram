import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/app_models.dart';
import 'accounts_screen.dart';
import 'tasks_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'logs_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _pages = [
    AccountsScreen(),
    TasksScreen(),
    HistoryScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  static const _navItems = [
    NavigationRailDestination(
      icon: Icon(Icons.people_outline_rounded),
      selectedIcon: Icon(Icons.people_rounded),
      label: Text('账号'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.copy_all_outlined),
      selectedIcon: Icon(Icons.copy_all_rounded),
      label: Text('任务'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history_rounded),
      label: Text('记录'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.list_alt_outlined),
      selectedIcon: Icon(Icons.list_alt_rounded),
      label: Text('日志'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('设置'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: Row(
            children: [
              _buildSidebar(context, provider),
              Expanded(child: _pages[provider.currentIndex]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context, AppProvider provider) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: primary.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Logo
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, theme.colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            'Cloner',
            style: TextStyle(
              color: primary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 8),
          // Nav items
          ...List.generate(_navItems.length, (i) {
            final selected = provider.currentIndex == i;
            final item = _navItems[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: InkWell(
                onTap: () => provider.setCurrentIndex(i),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected ? primary.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: selected
                        ? Border.all(color: primary.withValues(alpha: 0.3))
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          color: selected
                              ? primary
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white38
                                  : Colors.black38),
                          size: 22,
                        ),
                        child: selected
                            ? (item.selectedIcon)
                            : item.icon,
                      ),
                      const SizedBox(height: 3),
                      DefaultTextStyle(
                        style: TextStyle(
                          color: selected
                              ? primary
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white38
                                  : Colors.black38),
                          fontSize: 10,
                        ),
                        child: item.label,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // 运行状态指示
          _RunningIndicator(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _RunningIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final running = provider.tasks.where((t) => t.status == TaskStatus.running).length;
        if (running == 0) return const SizedBox.shrink();
        return Column(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$running运行',
              style: const TextStyle(color: Color(0xFF00E676), fontSize: 9),
            ),
          ],
        );
      },
    );
  }
}
