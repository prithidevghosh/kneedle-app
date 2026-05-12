import 'package:flutter/material.dart';

import 'doctor_report_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'pain_journal_screen.dart';
import 'reminders_screen.dart';

/// Bottom-nav shell. Replaces the stacked button list — primary surfaces are
/// one tap away, secondary actions (gait capture, exercise coach) live inside
/// the Home tab as featured cards.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    HomeScreen(),
    PainJournalScreen(),
    RemindersScreen(),
    HistoryScreen(),
    DoctorReportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFEAE4D5), width: 1),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.spa_outlined),
                selectedIcon: Icon(Icons.spa_rounded),
                label: 'Today',
              ),
              NavigationDestination(
                icon: Icon(Icons.mic_none_rounded),
                selectedIcon: Icon(Icons.mic_rounded),
                label: 'Journal',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_none_rounded),
                selectedIcon: Icon(Icons.notifications_rounded),
                label: 'Reminders',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart_rounded),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Insights',
              ),
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description_rounded),
                label: 'Report',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
