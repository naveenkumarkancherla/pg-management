import 'package:flutter/material.dart';

import 'api.dart';
import 'auth_screen.dart';
import 'dashboard_tab.dart';
import 'onboarding_screen.dart';
import 'payments_tab.dart';
import 'rooms_tab.dart';
import 'tenants_tab.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List _pgs = [];
  int? _pgId;
  int _tab = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pgs = await Api.pgs();
      setState(() {
        _pgs = pgs;
        _pgId = pgs.isNotEmpty ? pgs.first['id'] as int : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addPg() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New PG'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      try {
        await Api.post('/api/pgs/', {'name': name.text.trim(), 'address': address.text.trim()});
        if (mounted) snack(context, 'PG created');
        await _load();
      } catch (e) {
        if (mounted) snack(context, '$e');
      }
    }
  }

  Future<void> _logout() async {
    await Api.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GradientScaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return GradientScaffold(
        appBar: AppBar(title: const Text('PG Management')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              const SizedBox(height: 8),
              TextButton(onPressed: _logout, child: const Text('Log out')),
            ]),
          ),
        ),
      );
    }

    if (_pgs.isEmpty) {
      return GradientScaffold(
        appBar: AppBar(title: const Text('Welcome'), actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ]),
        body: OnboardingScreen(onDone: () {
          _load().then((_) {
            if (mounted) setState(() => _tab = 1); // land on Rooms to add floors/rooms
          });
        }),
      );
    }

    final id = _pgId!;
    final tabs = [
      DashboardTab(key: ValueKey('dash-$id'), pgId: id),
      RoomsTab(key: ValueKey('rooms-$id'), pgId: id),
      TenantsTab(key: ValueKey('tenants-$id'), pgId: id),
      PaymentsTab(key: ValueKey('pay-$id'), pgId: id),
    ];
    const titles = ['Dashboard', 'Availability', 'Inmates', 'Payments'];

    return GradientScaffold(
      appBar: AppBar(
        title: _pgs.length > 1
            ? InkWell(
                onTap: () async {
                  final picked = await pickItem<Map>(
                    context,
                    title: 'Select PG',
                    items: _pgs.cast<Map>(),
                    labelOf: (p) => '${p['name']}',
                  );
                  if (picked != null) setState(() => _pgId = picked['id'] as int);
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text('${_pgs.firstWhere((p) => p['id'] == _pgId, orElse: () => _pgs.first)['name']}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold, fontSize: 18))),
                  const Icon(Icons.arrow_drop_down, color: kGreen),
                ]),
              )
            : Text('${_pgs.first['name']}'),
        actions: [
          IconButton(onPressed: _addPg, icon: const Icon(Icons.add_business), tooltip: 'Add PG'),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Log out'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(titles[_tab], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kGreen)),
            ),
          ),
          // Show only the active tab (not IndexedStack) so it re-fetches each switch.
          Expanded(child: tabs[_tab]),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.meeting_room_outlined), selectedIcon: Icon(Icons.meeting_room), label: 'Rooms'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Inmates'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Payments'),
        ],
      ),
    );
  }
}
