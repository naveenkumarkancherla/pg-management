import 'package:flutter/material.dart';

import 'api.dart';
import 'main.dart';
import 'theme.dart';
import 'widgets.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Future<List> _future;

  @override
  void initState() {
    super.initState();
    _future = Api.plans();
  }

  void _reload() => setState(() {
        _future = Api.plans();
      });

  Future<void> _pay(Map plan) async {
    try {
      // create a real Razorpay (test-mode) order, then activate (dev). Production
      // swaps activate for the Razorpay checkout + /subscription/verify/ flow.
      await Api.createOrder(plan['id'] as int);
      await Api.activateTest(plan['id'] as int);
      if (mounted) {
        snack(context, 'Payment successful — welcome!');
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RootDecider()));
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _logout() async {
    await Api.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RootDecider()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Choose a plan'),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
      ),
      body: AsyncView<List>(
        future: _future,
        onRetry: _reload,
        builder: (c, plans) {
          if (plans.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No plans available yet. Please contact support.')));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Subscribe to start managing your PGs.', style: TextStyle(color: Colors.black54)),
            ),
            for (final p in plans)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kGreen)),
                    const SizedBox(height: 4),
                    Text('₹${p['price']} · ${p['duration_days']} days', style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: BusyButton(label: 'Pay ₹${p['price']}', onPressed: () => _pay(p)),
                    ),
                  ]),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Test mode — no real charge.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black45)),
            ),
          ]);
        },
      ),
    );
  }
}
