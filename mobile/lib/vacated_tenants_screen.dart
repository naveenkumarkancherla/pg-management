import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

/// Read-only list of vacated tenants (kept for future reference), across all PGs.
/// Filterable by name. Vacated tenants no longer hold a berth, so their old PG/room
/// isn't shown — the preserved details are name, phone, dates and deposit.
class VacatedTenantsScreen extends StatefulWidget {
  const VacatedTenantsScreen({super.key});
  @override
  State<VacatedTenantsScreen> createState() => _VacatedTenantsScreenState();
}

class _VacatedTenantsScreenState extends State<VacatedTenantsScreen> {
  late Future<List> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List> _fetch() => Api.vacatedTenants(query: _search.isEmpty ? null : _search);
  void _reload() => setState(() => _future = _fetch());

  // Right-side thumbnail of the tenant's stored file (ID/Aadhaar); tap to view full.
  Widget _file(BuildContext context, ImageProvider? img) {
    if (img == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: GestureDetector(
        onTap: () => viewImage(context, img),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(image: img, width: 54, height: 54, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Icon(icon, size: 13, color: Colors.black45),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('Vacated tenants'), backgroundColor: kGreen, foregroundColor: Colors.white),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name or mobile', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
            onChanged: (v) {
              _search = v;
              _reload();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: AsyncView<List>(
              future: _future,
              onRetry: _reload,
              builder: (c, tenants) {
                if (tenants.isEmpty) {
                  return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No vacated tenants.')))]);
                }
                return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
                  for (final t in tenants)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey.shade300,
                            child: Text('${t['name']}'.isNotEmpty ? '${t['name']}'[0].toUpperCase() : '?', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kGreen)),
                              _row(Icons.phone, '${t['phone']}'),
                              if ('${t['whatsapp'] ?? ''}'.isNotEmpty) _row(Icons.chat, '${t['whatsapp']}'),
                              _row(Icons.login, 'Joined ${t['join_date'] ?? '—'}'),
                              _row(Icons.logout, 'Vacated ${t['vacate_date'] ?? '—'}'),
                              _row(Icons.savings, 'Deposit ₹${t['deposit_amount'] ?? 0}'),
                            ]),
                          ),
                          _file(context, photoProvider('${t['photo'] ?? ''}')),
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
