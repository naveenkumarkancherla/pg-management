import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Right after payment, when the owner has no PGs.
/// Step 1: how many PGs. Step 2: name each PG + how many floors it has.
/// Creates each PG and its floors (named 1..N), then hands off to the Rooms tab.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _count = TextEditingController(text: '1');
  List<TextEditingController> _names = [];
  List<TextEditingController> _locations = [];
  List<TextEditingController> _floors = [];

  void _toNames() {
    final n = int.tryParse(_count.text) ?? 0;
    if (n < 1) {
      snack(context, 'Enter at least 1');
      return;
    }
    setState(() {
      _names = List.generate(n, (_) => TextEditingController());
      _locations = List.generate(n, (_) => TextEditingController());
      _floors = List.generate(n, (_) => TextEditingController(text: '1'));
      _step = 1;
    });
  }

  Future<void> _create() async {
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < _names.length; i++) {
      final name = _names[i].text.trim();
      if (name.isEmpty) continue;
      entries.add({
        'name': name,
        'address': _locations[i].text.trim(),
        'floors': int.tryParse(_floors[i].text) ?? 1,
      });
    }
    if (entries.isEmpty) {
      snack(context, 'Enter at least one PG name');
      return;
    }
    final done = await runTask(context, () async {
      for (final e in entries) {
        final pg = await Api.post('/api/pgs/', {'name': e['name'], 'address': e['address']}) as Map;
        final floors = e['floors'] as int;
        // Ground = 0, then 1, 2… so N floors are named 0..N-1.
        for (var f = 0; f < floors; f++) {
          await Api.post('/api/floors/', {'pg': pg['id'], 'name': '$f'});
        }
      }
    }, success: 'Setup complete — now add rooms & berths');
    if (done) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 12),
        const Icon(Icons.apartment, size: 56, color: kGreen),
        const SizedBox(height: 8),
        const Text("Let's set up your PGs", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kGreen)),
        const SizedBox(height: 20),
        if (_step == 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Text('How many PGs do you manage?'),
                const SizedBox(height: 14),
                TextField(controller: _count, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(border: OutlineInputBorder())),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _toNames, child: const Text('Next'))),
              ]),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Name each PG and its number of floors', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                for (int i = 0; i < _names.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kMint.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      TextField(controller: _names[i], decoration: InputDecoration(labelText: 'PG ${i + 1} name', border: const OutlineInputBorder(), filled: true, fillColor: Colors.white)),
                      const SizedBox(height: 12),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          flex: 3,
                          child: TextField(controller: _locations[i], decoration: const InputDecoration(labelText: 'Location / address', border: OutlineInputBorder(), filled: true, fillColor: Colors.white)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextField(controller: _floors[i], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Floors', border: OutlineInputBorder(), filled: true, fillColor: Colors.white)),
                        ),
                      ]),
                    ]),
                  ),
                const SizedBox(height: 4),
                SizedBox(width: double.infinity, child: BusyButton(label: 'Create & continue', onPressed: _create)),
                Center(child: TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Back'))),
              ]),
            ),
          ),
      ]),
    );
  }
}
