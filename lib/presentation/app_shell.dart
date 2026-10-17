import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/detection/presentation/home_scan_controller.dart';
import '../features/detection/presentation/home_screen.dart';
import '../features/harvest/presentation/harvest_planner_screen.dart';
import '../features/history/presentation/history_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final HomeScanController _scanController = HomeScanController();
  late final List<Widget?> _pages = [
    HomeScreen(
      scanController: _scanController,
      onOpenHarvest: () => _select(1),
    ),
    null,
    null,
    null,
  ];
  int _selectedIndex = 0;

  Widget _pageAt(int index) {
    return _pages[index] ??= switch (index) {
      1 => const HarvestPlannerScreen(),
      2 => const HistoryScreen(),
      3 => const ChatScreen(),
      _ => throw StateError('Unknown navigation index'),
    };
  }

  void _select(int index) => setState(() => _selectedIndex = index);

  void _openScan() {
    if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scanController.openScan());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pageAt(_selectedIndex),
      bottomNavigationBar: OrchardBottomNavigation(
        selectedIndex: _selectedIndex,
        onDashboard: () => _select(0),
        onHarvest: () => _select(1),
        onScan: _openScan,
        onHistory: () => _select(2),
        onAssistant: () => _select(3),
      ),
    );
  }
}

class OrchardBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final VoidCallback onDashboard;
  final VoidCallback onHarvest;
  final VoidCallback onScan;
  final VoidCallback onHistory;
  final VoidCallback onAssistant;

  const OrchardBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDashboard,
    required this.onHarvest,
    required this.onScan,
    required this.onHistory,
    required this.onAssistant,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 98,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 4,
              left: 10,
              right: 10,
              height: 90,
              child: CustomPaint(
                painter: _OrchardDockPainter(
                  surface: Theme.of(context).colorScheme.surface,
                  border: AppColors.outlineTint,
                ),
              ),
            ),
            Positioned.fill(
              top: 28,
              bottom: 11,
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      label: 'Dashboard',
                      displayLabel: 'HOME',
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      selected: selectedIndex == 0,
                      onTap: onDashboard,
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      label: 'Harvest plan',
                      displayLabel: 'HARVEST',
                      icon: Icons.calendar_month_outlined,
                      selectedIcon: Icons.calendar_month_rounded,
                      selected: selectedIndex == 1,
                      onTap: onHarvest,
                    ),
                  ),
                  const SizedBox(width: 84),
                  Expanded(
                    child: _NavItem(
                      label: 'History',
                      displayLabel: 'RECORDS',
                      icon: Icons.receipt_long_outlined,
                      selectedIcon: Icons.receipt_long_rounded,
                      selected: selectedIndex == 2,
                      onTap: onHistory,
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      label: 'AI assistant',
                      displayLabel: 'ADVISOR',
                      icon: Icons.psychology_alt_outlined,
                      selectedIcon: Icons.psychology_alt_rounded,
                      selected: selectedIndex == 3,
                      onTap: onAssistant,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Start mango scan',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onScan,
                  customBorder: const CircleBorder(),
                  child: Ink(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withOpacity(.24),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.botanicalGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.center_focus_strong_rounded,
                              color: Colors.white,
                              size: 25,
                            ),
                            SizedBox(height: 1),
                            Text(
                              'SCAN',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final String displayLabel;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.displayLabel,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 34,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? primary.withOpacity(.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    color: selected ? primary : AppColors.mutedGraphite,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayLabel,
                  style: TextStyle(
                    color: selected ? primary : AppColors.mutedGraphite,
                    fontFamily: 'monospace',
                    fontSize: 8,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: .25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrchardDockPainter extends CustomPainter {
  final Color surface;
  final Color border;

  const _OrchardDockPainter({required this.surface, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final path = Path()
      ..moveTo(0, 30)
      ..quadraticBezierTo(0, 17, 14, 17)
      ..lineTo(center - 53, 17)
      ..cubicTo(center - 35, 17, center - 31, 1, center, 1)
      ..cubicTo(center + 31, 1, center + 35, 17, center + 53, 17)
      ..lineTo(size.width - 14, 17)
      ..quadraticBezierTo(size.width, 17, size.width, 30)
      ..lineTo(size.width, size.height - 20)
      ..quadraticBezierTo(
          size.width, size.height - 4, size.width - 18, size.height - 4)
      ..lineTo(18, size.height - 4)
      ..quadraticBezierTo(0, size.height - 4, 0, size.height - 20)
      ..close();

    canvas.drawShadow(path, Colors.black.withOpacity(.18), 10, false);
    canvas.drawPath(path, Paint()..color = surface);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _OrchardDockPainter oldDelegate) =>
      oldDelegate.surface != surface || oldDelegate.border != border;
}
