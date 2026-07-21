import 'package:flutter/material.dart';

import 'api.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'payment_screen.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {

  // Surface any widget-build error on screen instead of a blank page.
  ErrorWidget.builder = (details) => Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Text('Something went wrong:\n\n${details.exception}',
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ),
      );

  // When a refresh fails, drop the user back to login (once).
  Api.onSessionExpired = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootDecider()),
      (route) => false,
    );
  };
  runApp(const PgApp());
}

class PgApp extends StatelessWidget {
  const PgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PG Management',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootDecider(),
    );
  }
}

/// Decides where to land: not logged in → login; logged in but not paid → payment;
/// paid → dashboard. Used at startup and after login/register/payment.
class RootDecider extends StatefulWidget {
  const RootDecider({super.key});
  @override
  State<RootDecider> createState() => _RootDeciderState();
}

class _RootDeciderState extends State<RootDecider> {
  Widget? _screen;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // Stay logged in until the user explicitly logs out: only a genuine auth failure
    // (session rejected) sends them to login. A slow/sleeping server or network blip
    // keeps them in the app.
    Widget next = const AuthScreen();
    if (await Api.isLoggedIn()) {
      try {
        final me = await Api.me().timeout(const Duration(seconds: 30));
        next = me['has_access'] == true ? const HomeScreen() : const PaymentScreen();
      } on ApiException catch (e) {
        next = e.status == 401 ? const AuthScreen() : const HomeScreen();
      } catch (_) {
        next = const HomeScreen(); // timeout/other transient issue → stay logged in
      }
    }
    if (mounted) setState(() => _screen = next);
  }

  @override
  Widget build(BuildContext context) {
    return _screen ?? const GradientScaffold(body: Center(child: CircularProgressIndicator()));
  }
}
