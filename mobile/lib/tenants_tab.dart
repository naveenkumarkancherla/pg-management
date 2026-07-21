import 'package:flutter/material.dart';

import 'api.dart';
import 'add_tenant_screen.dart';
import 'theme.dart';
import 'vacated_tenants_screen.dart';
import 'widgets.dart';

class TenantsTab extends StatefulWidget {
  final int pgId;
  const TenantsTab({super.key, required this.pgId});
  @override
  State<TenantsTab> createState() => _TenantsTabState();
}

class _TenantsTabState extends State<TenantsTab> {
  late Future<List> _future;
  String _filter = 'all'; // all | active | unpaid
  String _search = '';
  bool _showRent = false; // rent hidden by default

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List> _fetch() => Api.tenants(
        widget.pgId,
        activeOnly: _filter == 'active',
        paymentStatus: _filter == 'unpaid' ? 'unpaid' : null,
        name: _search.isEmpty ? null : _search,
      );

  void _reload() => setState(() {
        _future = _fetch();
      });

  // ---- Collect (additive; join-anchored cycle; shows pending) ----
  Future<void> _collect(Map t) async {
    final cp = (t['current_payment'] as Map?) ?? const {};
    double num0(v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    final rent = num0(t['current_rent']);
    final now = DateTime.now();

    var due = num0(cp['due'] ?? rent);
    var paidSoFar = num0(cp['paid']);
    var pending = num0(cp['pending'] ?? due);
    var pm = (cp['period_month'] is int) ? cp['period_month'] as int : now.month;
    var py = (cp['period_year'] is int) ? cp['period_year'] as int : now.year;
    var advance = false;

    // Current cycle already cleared → offer to collect the next cycle in advance.
    if ('${cp['status']}' == 'paid') {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Cycle already cleared ✓'),
          content: Text('${t['name']} has fully paid the $pm/$py cycle. Collect an advance for the next cycle?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Next cycle')),
          ],
        ),
      );
      if (go != true || !mounted) return;
      advance = true;
      if (pm == 12) {
        pm = 1;
        py += 1;
      } else {
        pm += 1;
      }
      due = rent;
      paidSoFar = 0;
      pending = rent;
    }

    final month = TextEditingController(text: '$pm');
    final year = TextEditingController(text: '$py');
    final amount = TextEditingController(text: pending > 0 ? pending.toStringAsFixed(0) : '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setLocal) {
        final received = double.tryParse(amount.text) ?? 0;
        final afterBalance = pending - received;
        final statusLine = received <= 0
            ? 'Enter amount received'
            : (afterBalance > 0 ? 'Still ₹${afterBalance.toStringAsFixed(0)} pending after this' : 'Clears the dues ✓');
        return AlertDialog(
          title: Text('Collect · ${t['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kMint.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
              child: Text('Rent ₹${due.toStringAsFixed(0)}  ·  Paid ₹${paidSoFar.toStringAsFixed(0)}  ·  Pending ₹${pending.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: month, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder()))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 14),
            TextField(controller: amount, keyboardType: TextInputType.number, onChanged: (_) => setLocal(() {}), decoration: const InputDecoration(labelText: 'Amount received now', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: Text(statusLine, style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        );
      }),
    );
    if (ok == true && mounted) {
      final done = await runTask(context, () async {
        await Api.post('/api/tenants/${t['id']}/collect/', {
          'month': int.tryParse(month.text) ?? pm,
          'year': int.tryParse(year.text) ?? py,
          'amount_paid': amount.text,
          if (advance) 'amount_due': due.toStringAsFixed(2),
        });
      }, success: 'Payment recorded');
      if (done) _reload();
    }
  }

  // ---- Move (searchable berth) ----
  Future<void> _move(Map t) async {
    final vacant = await Api.berths(widget.pgId, status: 'vacant');
    if (!mounted) return;
    if (vacant.isEmpty) {
      snack(context, 'No vacant berths');
      return;
    }
    Map berth = vacant.first as Map;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text('Move · ${t['name']}'),
          content: SearchableField<Map>(
            label: 'New berth',
            value: berth,
            items: vacant.cast<Map>(),
            labelOf: (b) => '${b['floor_name']} / Room ${b['room_number']} / Bed ${b['label']}',
            onSelected: (b) => setLocal(() => berth = b),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final done = await runTask(context, () async {
        await Api.post('/api/tenants/${t['id']}/move/', {'berth_id': berth['id']});
      }, success: 'Moved');
      if (done) _reload();
    }
  }

  Future<void> _vacate(Map t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Vacate ${t['name']}?'),
        content: Text('Deposit on file: ₹${t['deposit_amount'] ?? 0}. Frees the berth and marks the tenant vacated.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vacate')),
        ],
      ),
    );
    if (ok == true && mounted) {
      final done = await runTask(context, () async {
        await Api.post('/api/tenants/${t['id']}/vacate/', {});
      }, success: 'Vacated');
      if (done) _reload();
    }
  }

  Future<void> _history(Map t) async {
    try {
      final payments = await Api.get('/api/tenants/${t['id']}/payments/') as List;
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (c) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('${t['name']} · payments', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kGreen)),
          const SizedBox(height: 8),
          if (payments.isEmpty) const Text('No payments recorded'),
          for (final p in payments)
            ListTile(
              dense: true,
              title: Text('${p['month']}/${p['year']}'),
              subtitle: Text('${p['status']}'),
              trailing: Text('₹${p['amount_paid']} / ₹${p['amount_due']}'),
            ),
        ]),
      );
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _edit(Map t) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddTenantScreen(pgId: widget.pgId, tenant: t)));
    if (saved == true) _reload();
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddTenantScreen(pgId: widget.pgId)));
    if (added == true) _reload();
  }

  Widget _tag(String label, Color color, [IconData? icon]) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ]),
      );

  Color _cardBorderColor(Map t) {
    if (t['is_active'] != true) return Colors.grey.shade300;
    switch ('${t['current_payment']?['status']}') {
      case 'paid':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      default:
        return Colors.redAccent;
    }
  }

  Widget _payBadge(Map t) {
    final status = '${t['current_payment']?['status'] ?? 'unpaid'}';
    switch (status) {
      case 'paid':
        return _tag('Paid', Colors.green.shade700, Icons.check_circle);
      case 'partial':
        return _tag('Partial', Colors.orange.shade800, Icons.timelapse);
      default:
        return _tag('Unpaid', Colors.redAccent, Icons.error_outline);
    }
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Icon(icon, size: 20, color: kBrown),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 10, color: kBrown)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('Add tenant')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
            onChanged: (v) {
              _search = v;
              _reload();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final f in const ['all', 'active', 'unpaid'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f == 'unpaid' ? 'unpaid/partial' : f),
                  selected: _filter == f,
                  onSelected: (_) => setState(() {
                    _filter = f;
                    _future = _fetch();
                  }),
                ),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Vacated tenants',
              icon: const Icon(Icons.history_toggle_off, color: kBrown),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VacatedTenantsScreen())),
            ),
            IconButton(
              tooltip: _showRent ? 'Hide rent' : 'Show rent',
              icon: Icon(_showRent ? Icons.visibility : Icons.visibility_off, color: kBrown),
              onPressed: () => setState(() => _showRent = !_showRent),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: AsyncView<List>(
              future: _future,
              onRetry: _reload,
              builder: (c, tenants) {
                if (tenants.isEmpty) {
                  return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No tenants. Tap “Add tenant”.')))]);
                }
                return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), children: [
                  for (final t in tenants)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: _cardBorderColor(t), width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                        child: Column(children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: kGreen.withValues(alpha: 0.15),
                              child: Text('${t['name']}'.isNotEmpty ? '${t['name']}'[0].toUpperCase() : '?', style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold, fontSize: 18)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kGreen)),
                                const SizedBox(height: 2),
                                Row(children: [
                                  const Icon(Icons.phone, size: 12, color: Colors.black45),
                                  const SizedBox(width: 4),
                                  Text('${t['phone']}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                ]),
                                const SizedBox(height: 2),
                                Row(children: [
                                  Icon(t['location'] != null ? Icons.bed : Icons.logout, size: 12, color: Colors.black45),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text('${t['location'] ?? 'Vacated'}', style: const TextStyle(fontSize: 11, color: Colors.black54))),
                                ]),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              if (t['current_rent'] != null)
                                Text(_showRent ? '₹${t['current_rent']}' : '₹ •••', style: const TextStyle(fontWeight: FontWeight.bold, color: kGreen)),
                              const SizedBox(height: 4),
                              t['is_active'] == true ? _payBadge(t) : _tag('Vacated', Colors.grey),
                            ]),
                          ]),
                          const Divider(height: 14),
                          Row(children: [
                            _action(Icons.currency_rupee, 'Collect', () => _collect(t)),
                            _action(Icons.edit, 'Edit', () => _edit(t)),
                            _action(Icons.swap_horiz, 'Move', () => _move(t)),
                            _action(Icons.history, 'History', () => _history(t)),
                            _action(Icons.directions_walk, 'Vacate', () => _vacate(t)),
                          ]),
                        ]),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ),
      ]),
    );
  }
}
