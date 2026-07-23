import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bills / expenses for one PG. Shows this month's list and lets the owner add more.
class ExpensesScreen extends StatefulWidget {
  final int pgId;
  const ExpensesScreen({super.key, required this.pgId});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<List> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  // Current month only; the calendar month's real day count (28/30/31) is applied
  // server-side via spent_on month/year, so each month cycle scopes itself.
  Future<List> _fetch() {
    final now = DateTime.now();
    return Api.expenses(widget.pgId, month: now.month, year: now.year);
  }
  void _reload() => setState(() => _future = _fetch());

  double _num(v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;

  Future<void> _add() async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final category = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add expense'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'What for? (e.g. Electricity bill)')),
          const SizedBox(height: 8),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount ₹')),
          const SizedBox(height: 8),
          TextField(controller: category, decoration: const InputDecoration(labelText: 'Category (optional) e.g. utilities')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (title.text.trim().isEmpty || (double.tryParse(amount.text) ?? 0) <= 0) {
      snack(context, 'Enter a title and a valid amount');
      return;
    }
    final done = await runTask(context, () async {
      await Api.addExpense(widget.pgId,
          title: title.text.trim(), amount: amount.text.trim(), category: category.text.trim());
    }, success: 'Expense added');
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('Expenses'), backgroundColor: kGreen, foregroundColor: Colors.white),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add expense')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List>(
          future: _future,
          onRetry: _reload,
          builder: (c, items) {
            final total = items.fold<double>(0, (s, e) => s + _num(e['amount']));
            return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
              StatCard(label: 'Total spent', value: '₹${total.toStringAsFixed(0)}', icon: Icons.account_balance_wallet),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No expenses yet. Tap “Add expense”.')))
              else
                for (final e in items)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0x22B26A00), child: Icon(Icons.receipt_long, color: kBrown, size: 18)),
                      title: Text('${e['title']}', style: const TextStyle(fontWeight: FontWeight.w600, color: kGreen)),
                      subtitle: Text([
                        if ('${e['category'] ?? ''}'.isNotEmpty) '${e['category']}',
                        fmtDateTime(e['created_at']),
                      ].join(' · ')),
                      trailing: Text('₹${e['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
            ]);
          },
        ),
      ),
    );
  }
}
