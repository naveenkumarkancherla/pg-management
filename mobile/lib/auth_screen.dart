import 'package:flutter/material.dart';

import 'api.dart';
import 'main.dart';
import 'theme.dart';
import 'widgets.dart';

class AuthScreen extends StatefulWidget {
  final String? flash; // one-off message to show on arrival (e.g. after logout)
  const AuthScreen({super.key, this.flash});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.flash != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) snack(context, widget.flash!);
      });
    }
  }

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  bool _register = false; // false = login, true = register
  bool _obscure = true; // password hidden by default
  String _msg = '';

  void _toRoot() => Navigator.of(context)
      .pushReplacement(MaterialPageRoute(builder: (_) => const RootDecider()));

  // Indian mobile: 10 digits starting 6-9, optional +91/91/0 prefix.
  bool _validPhone(String p) =>
      RegExp(r'^(?:\+?91|0)?[6-9]\d{9}$').hasMatch(p.replaceAll(RegExp(r'[\s-]'), ''));

  Future<void> _submit() async {
    setState(() => _msg = '');
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty || (_register && _phone.text.trim().isEmpty)) {
      setState(() => _msg = 'Please fill all fields.');
      return;
    }
    if (_register && !_validPhone(_phone.text.trim())) {
      setState(() => _msg = 'Enter a valid 10-digit mobile number.');
      return;
    }
    try {
      if (_register) {
        await Api.register(email, _password.text, _phone.text.trim());
        await Api.login(email, _password.text); // auto-login → RootDecider sends to payment
      } else {
        await Api.login(email, _password.text);
      }
      if (mounted) _toRoot();
    } catch (e) {
      setState(() => _msg = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.home_work, size: 48, color: kGreen),
                  const SizedBox(height: 8),
                  if (_register)
                    const Text('Create account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kGreen))
                  else
                    // "PG" serif wordmark logo
                    const Text('PG', style: TextStyle(fontFamily: 'Serif', fontSize: 58, fontWeight: FontWeight.w800, color: kGreen, letterSpacing: 1, height: 1.0)),
                  const SizedBox(height: 20),
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', filled: true, fillColor: Colors.white)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', filled: true, fillColor: Colors.white)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: BusyButton(label: _register ? 'Register' : 'Login', onPressed: _submit),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _register = !_register;
                      _msg = '';
                    }),
                    child: Text(_register ? 'Have an account? Log in' : "New here? Create an account"),
                  ),
                  if (_msg.isNotEmpty)
                    Text(_msg, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
