import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Month/year-wise income (rent collected), with spent + net, newest first.
class IncomeHistoryScreen extends StatefulWidget {
  final int pgId;
  const IncomeHistoryScreen({super.key, required this.pgId});
  @override
  State<IncomeHistoryScreen> createState() => _IncomeHistoryScreenState();
}

class _IncomeHistoryScreenState extends State<IncomeHistoryScreen> {
  late Future<List> _future;

  @override
  void initState() {
    super.initState();
    _future = Api.monthlyIncome(widget.pgId);
  }

  void _reload() => setState(() => _future = Api.monthlyIncome(widget.pgId));

  Widget _cell(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black45)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('Monthly income'), backgroundColor: kGreen, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List>(
          future: _future,
          onRetry: _reload,
          builder: (c, months) {
            if (months.isEmpty) {
              return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No income recorded yet.')))]);
            }
            return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
              for (final m in months)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Expanded(
                        child: Text('${monthName(m['month'])} ${m['year']}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kGreen)),
                      ),
                      _cell('Income', '₹${m['income']}', kGreen),
                      const SizedBox(width: 16),
                      _cell('Spent', '₹${m['spent']}', kBrown),
                      const SizedBox(width: 16),
                      _cell('Net', '₹${m['net']}', (m['net'] ?? 0) < 0 ? Colors.redAccent : Colors.black87),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
