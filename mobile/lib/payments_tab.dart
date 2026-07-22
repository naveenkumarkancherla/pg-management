import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

class PaymentsTab extends StatefulWidget {
  final int pgId;
  const PaymentsTab({super.key, required this.pgId});
  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  late Future<List> _future;
  String _status = 'all'; // all | paid | partial | unpaid

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List> _fetch() => Api.payments(widget.pgId, status: _status == 'all' ? null : _status);
  void _reload() => setState(() {
        _future = _fetch();
      });

  static const _colors = {
    'paid': Colors.green,
    'partial': Colors.orange,
    'unpaid': Colors.redAccent,
  };

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final s in const ['all', 'paid', 'partial', 'unpaid'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s),
                selected: _status == s,
                onSelected: (_) => setState(() {
                  _status = s;
                  _future = _fetch();
                }),
              ),
            ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: AsyncView<List>(
            future: _future,
            onRetry: _reload,
            builder: (c, payments) {
              if (payments.isEmpty) {
                return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No payments recorded yet.')))]);
              }
              return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
                for (final p in payments)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (_colors[p['status']] ?? Colors.grey).withValues(alpha: 0.15),
                        child: Icon(Icons.currency_rupee, color: _colors[p['status']] ?? Colors.grey, size: 18),
                      ),
                      title: Text('${p['tenant_name']}', style: const TextStyle(fontWeight: FontWeight.w600, color: kGreen)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['month']}/${p['year']} · ${p['status']}'),
                        if (p['payment_date'] != null)
                          Text('Paid ${fmtDateTime(p['payment_date'])}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                      ]),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('₹${p['amount_paid']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('of ₹${p['amount_due']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    ]);
  }
}
