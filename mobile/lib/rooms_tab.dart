import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

class RoomsTab extends StatefulWidget {
  final int pgId;
  const RoomsTab({super.key, required this.pgId});
  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<RoomsTab> {
  late Future<List> _future;
  String _status = 'all'; // all | vacant | occupied
  String _floor = 'All'; // floor-name filter
  bool _showRent = false; // rent hidden by default

  @override
  void initState() {
    super.initState();
    _future = Api.berths(widget.pgId);
  }

  void _reload() => setState(() {
        _future = Api.berths(widget.pgId);
      });

  // ---- Add single room ----
  Future<void> _addRoom() async {
    final floors = await Api.floors(widget.pgId);
    if (!mounted) return;
    if (floors.isEmpty) {
      snack(context, 'No floors yet — set them up during onboarding or ask us to add floor support here.');
      return;
    }
    Map floor = floors.first as Map;
    final number = TextEditingController();
    final rent = TextEditingController(text: '5000');
    final sharing = TextEditingController(text: '2'); // default 2-sharing
    final type = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Add room'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SearchableField<Map>(
                label: 'Floor',
                value: floor,
                items: floors.cast<Map>(),
                labelOf: (f) => 'Floor ${f['name']}',
                onSelected: (f) => setLocal(() => floor = f),
              ),
              const SizedBox(height: 14),
              TextField(controller: number, decoration: const InputDecoration(labelText: 'Room number', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: sharing, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Beds (sharing)', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rent', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextField(controller: type, decoration: const InputDecoration(labelText: 'Room type (AC / Non-AC)', border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && number.text.trim().isNotEmpty && mounted) {
      final done = await runTask(context, () async {
        await Api.post('/api/rooms/', {
          'floor': floor['id'],
          'number': number.text.trim(),
          'rent_amount': rent.text,
          'room_type': type.text,
          'berth_count': int.tryParse(sharing.text) ?? 2,
        });
      }, success: 'Room added');
      if (done) _reload();
    }
  }

  // ---- Bulk generate: multiple sharing types, each its own rent ----
  Map<String, TextEditingController> _newGroup() => {
        'prefix': TextEditingController(),
        'count': TextEditingController(text: '5'),
        'sharing': TextEditingController(text: '2'),
        'rent': TextEditingController(text: '5000'),
        'type': TextEditingController(),
      };

  Future<void> _generateRooms() async {
    final floors = await Api.floors(widget.pgId);
    if (!mounted) return;
    if (floors.isEmpty) {
      snack(context, 'No floors yet');
      return;
    }
    Map floor = floors.first as Map;
    final groups = <Map<String, TextEditingController>>[_newGroup()];

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Generate rooms'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SearchableField<Map>(
                  label: 'Floor',
                  value: floor,
                  items: floors.cast<Map>(),
                  labelOf: (f) => 'Floor ${f['name']}',
                  onSelected: (f) => setLocal(() => floor = f),
                ),
                const SizedBox(height: 10),
                const Text('Sharing types (each its own rent):', style: TextStyle(fontWeight: FontWeight.w600, color: kGreen)),
                for (int i = 0; i < groups.length; i++)
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: TextField(controller: groups[i]['prefix'], decoration: const InputDecoration(labelText: 'Prefix', isDense: true))),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: groups[i]['count'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rooms', isDense: true))),
                          if (groups.length > 1)
                            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setLocal(() => groups.removeAt(i))),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: TextField(controller: groups[i]['sharing'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Beds', isDense: true))),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: groups[i]['rent'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rent', isDense: true))),
                          const SizedBox(width: 6),
                          Expanded(child: TextField(controller: groups[i]['type'], decoration: const InputDecoration(labelText: 'Type', isDense: true))),
                        ]),
                      ]),
                    ),
                  ),
                TextButton.icon(onPressed: () => setLocal(() => groups.add(_newGroup())), icon: const Icon(Icons.add), label: const Text('Add sharing type')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Generate')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final done = await runTask(context, () async {
        await Api.post('/api/floors/${floor['id']}/generate_rooms/', {
          'groups': [
            for (final g in groups)
              {
                'prefix': g['prefix']!.text,
                'count': int.tryParse(g['count']!.text) ?? 0,
                'berths_per_room': int.tryParse(g['sharing']!.text) ?? 2,
                'rent_amount': g['rent']!.text,
                'room_type': g['type']!.text,
              },
          ],
        });
      }, success: 'Rooms generated');
      if (done) _reload();
    }
  }

  // ---- Edit room number ----
  Future<void> _editRoom(int roomId, String currentNumber) async {
    final number = TextEditingController(text: currentNumber);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit room number'),
        content: TextField(controller: number, autofocus: true, decoration: const InputDecoration(labelText: 'Room number', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && number.text.trim().isNotEmpty && mounted) {
      final done = await runTask(context, () async {
        await Api.patch('/api/rooms/$roomId/', {'number': number.text.trim()});
      }, success: 'Room updated');
      if (done) _reload();
    }
  }

  // ---- Delete room ----
  Future<void> _deleteRoom(int roomId, String number, bool anyOccupied) async {
    if (anyOccupied) {
      snack(context, 'Room $number has occupants — vacate them first');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete room $number?'),
        content: const Text('This removes the room and its (empty) berths.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      final done = await runTask(context, () async {
        await Api.delete('/api/rooms/$roomId/');
      }, success: 'Room deleted');
      if (done) _reload();
    }
  }

  // available = red (needs filling), occupied = green (filled) — interchanged per request
  Color _bedColor(String status) => status == 'vacant' ? Colors.redAccent : Colors.green;

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 12, color: c),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: PopupMenuButton<String>(
        onSelected: (v) => v == 'room' ? _addRoom() : _generateRooms(),
        itemBuilder: (c) => const [
          PopupMenuItem(value: 'room', child: ListTile(leading: Icon(Icons.meeting_room), title: Text('Add room'))),
          PopupMenuItem(value: 'bulk', child: ListTile(leading: Icon(Icons.grid_view), title: Text('Generate rooms'))),
        ],
        child: const FloatingActionButton(onPressed: null, child: Icon(Icons.add)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List>(
          future: _future,
          onRetry: _reload,
          builder: (c, allBerths) {
            final floorNames = <String>{for (final b in allBerths) '${b['floor_name']}'}.toList()..sort();
            final byStatus = _status == 'all' ? allBerths : allBerths.where((b) => b['status'] == _status).toList();
            final berths = _floor == 'All' ? byStatus : byStatus.where((b) => '${b['floor_name']}' == _floor).toList();

            // group by room id (not number) so two rooms with the same number never merge
            final byFloor = <String, Map<int, List>>{};
            for (final b in berths) {
              byFloor.putIfAbsent('${b['floor_name']}', () => {}).putIfAbsent(b['room'] as int, () => []).add(b);
            }
            return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  _legendDot(Colors.redAccent, 'Available'),
                  const SizedBox(width: 16),
                  _legendDot(Colors.green, 'Occupied'),
                  const Spacer(),
                  IconButton(
                    tooltip: _showRent ? 'Hide rent' : 'Show rent',
                    icon: Icon(_showRent ? Icons.visibility : Icons.visibility_off, color: kBrown),
                    onPressed: () => setState(() => _showRent = !_showRent),
                  ),
                ]),
              ),
              Row(children: [
                for (final s in const ['all', 'vacant', 'occupied'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s == 'vacant' ? 'available' : s),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              SearchableField<String>(
                label: 'Floor',
                value: _floor,
                items: ['All', ...floorNames],
                labelOf: (f) => f == 'All' ? 'All floors' : 'Floor $f',
                onSelected: (f) => setState(() => _floor = f),
              ),
              const SizedBox(height: 8),
              if (allBerths.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No rooms yet. Use + to add or generate rooms.'))),
              for (final floor in byFloor.keys) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Floor $floor', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kGreen)),
                ),
                for (final roomId in byFloor[floor]!.keys)
                  Builder(builder: (_) {
                    final beds = byFloor[floor]![roomId]!;
                    final number = '${beds.first['room_number']}';
                    final anyOccupied = beds.any((b) => b['status'] == 'occupied');
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.meeting_room, color: kBrown, size: 20),
                            const SizedBox(width: 8),
                            Text('Room $number', style: const TextStyle(fontWeight: FontWeight.bold, color: kGreen)),
                            const SizedBox(width: 8),
                            Text(_showRent ? '₹${beds.first['rent']}' : '₹ •••', style: const TextStyle(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 19, color: kBrown),
                              tooltip: 'Edit room number',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _editRoom(roomId, number),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              tooltip: 'Delete room',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _deleteRoom(roomId, number, anyOccupied),
                            ),
                          ]),
                          const Divider(),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final b in beds)
                              Chip(
                                avatar: Icon(Icons.bed, size: 16, color: _bedColor(b['status'])),
                                label: Text('${b['label']}${_showRent ? ' · ₹${b['rent']}' : ''}${b['tenant_name'] != null ? ' · ${b['tenant_name']}' : ''}'),
                                backgroundColor: _bedColor(b['status']).withValues(alpha: 0.12),
                              ),
                          ]),
                        ]),
                      ),
                    );
                  }),
              ],
            ]);
          },
        ),
      ),
    );
  }
}
