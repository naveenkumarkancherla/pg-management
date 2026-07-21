import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

class DashboardTab extends StatefulWidget {
  final int pgId;
  const DashboardTab({super.key, required this.pgId});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late Future<Map> _future;

  @override
  void initState() {
    super.initState();
    _future = Api.analytics(widget.pgId);
  }

  void _reload() => setState(() {
        _future = Api.analytics(widget.pgId);
      });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<Map>(
        future: _future,
        onRetry: _reload,
        builder: (c, a) {
          final col = a['collection'] as Map;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Row(children: [
              Expanded(child: StatCard(label: 'Total beds', value: '${a['berths_total']}', icon: Icons.bed)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Filled beds', value: '${a['berths_occupied']}', icon: Icons.bedtime)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Available', value: '${a['berths_vacant']}', icon: Icons.bed_outlined)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: StatCard(label: 'Occupancy', value: '${a['occupancy_pct']}%', icon: Icons.pie_chart)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Inmates', value: '${a['inmates']}', icon: Icons.people)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Vacated (MTD)', value: '${a['vacated_this_month']}', icon: Icons.directions_walk)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: StatCard(label: 'Collected (MTD)', value: '₹${a['revenue_this_month']}', icon: Icons.account_balance_wallet)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(label: 'Last month', value: '₹${a['revenue_last_month']}', icon: Icons.history)),
            ]),
            const SizedBox(height: 6),
            SectionCard(title: 'Collection this month', icon: Icons.receipt_long, children: [
              for (final s in const ['paid', 'partial', 'unpaid'])
                KeyValueRow('${s[0].toUpperCase()}${s.substring(1)}', '${col[s]['count']} · ₹${col[s]['amount']}'),
            ]),
          ]);
        },
      ),
    );
  }
}
