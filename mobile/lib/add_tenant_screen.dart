import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets.dart';

class AddTenantScreen extends StatefulWidget {
  final int pgId;
  final Map? tenant; // null = add, non-null = edit
  const AddTenantScreen({super.key, required this.pgId, this.tenant});
  @override
  State<AddTenantScreen> createState() => _AddTenantScreenState();
}

class _AddTenantScreenState extends State<AddTenantScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _deposit;
  final _rent = TextEditingController();
  final _paid = TextEditingController(); // optional first payment (partial or full)
  DateTime _joinDate = DateTime.now();

  List _vacant = [];
  Map? _berth;
  bool _loading = true;
  String? _error;
  // base64 data URL. null = untouched (don't send on edit → keep existing);
  // '' = explicitly removed; non-empty = new/loaded photo.
  String? _photo;

  bool get _isEdit => widget.tenant != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    _name = TextEditingController(text: t?['name'] ?? '');
    _phone = TextEditingController(text: t?['phone'] ?? '');
    _whatsapp = TextEditingController(text: t?['whatsapp'] ?? '');
    _deposit = TextEditingController(text: '${t?['deposit_amount'] ?? '0'}');
    _joinDate = t?['join_date'] != null ? DateTime.parse(t!['join_date']) : DateTime.now();
    if (_isEdit) {
      _rent.text = '${t?['current_rent'] ?? ''}';
      _loading = false;
      _loadPhoto(); // list omits the photo to stay light — fetch the full tenant
    } else {
      _loadVacant();
    }
  }

  // The tenant list drops `photo` for speed, so fetch the single tenant to show it.
  Future<void> _loadPhoto() async {
    try {
      final full = await Api.get('/api/tenants/${widget.tenant!['id']}/') as Map;
      if (mounted) setState(() => _photo = full['photo'] ?? '');
    } catch (_) {/* leave _photo null → save won't touch the stored photo */}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 900, imageQuality: 55);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _photo = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    } catch (e) {
      if (mounted) snack(context, 'Could not get image: $e');
    }
  }

  Future<void> _loadVacant() async {
    try {
      final v = await Api.berths(widget.pgId, status: 'vacant');
      setState(() {
        _vacant = v;
        _berth = v.isNotEmpty ? v.first as Map : null;
        _rent.text = _berth != null ? '${_berth!['rent']}' : '';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _error = 'Name and phone are required');
      return;
    }
    setState(() => _error = null);
    final body = {
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'whatsapp': _whatsapp.text.trim(),
      'join_date': _fmt(_joinDate),
      'deposit_amount': _deposit.text,
      if (_photo != null) 'photo': _photo, // null = leave the stored photo untouched
    };
    try {
      if (_isEdit) {
        await Api.patch('/api/tenants/${widget.tenant!['id']}/', body);
        final berthId = widget.tenant!['berth'];
        if (berthId != null && _rent.text.trim().isNotEmpty) {
          await Api.patch('/api/berths/$berthId/', {'rent_amount': _rent.text.trim()});
        }
      } else {
        // set the (possibly manual) rent on the berth, create the tenant,
        // then optionally record a first (partial or full) payment.
        if (_berth != null && _rent.text.trim().isNotEmpty) {
          await Api.patch('/api/berths/${_berth!['id']}/', {'rent_amount': _rent.text.trim()});
        }
        final t = await Api.post('/api/tenants/', {...body, if (_berth != null) 'berth': _berth!['id']}) as Map;
        // first-month due = rent + deposit; record it (with any first payment)
        if (_berth != null) {
          final rent = double.tryParse(_rent.text.trim()) ?? 0;
          final deposit = double.tryParse(_deposit.text.trim()) ?? 0;
          final now = DateTime.now();
          await Api.post('/api/tenants/${t['id']}/collect/', {
            'month': now.month,
            'year': now.year,
            'amount_paid': _paid.text.trim().isEmpty ? '0' : _paid.text.trim(),
            'amount_due': (rent + deposit).toStringAsFixed(2),
          });
        }
      }
      if (mounted) {
        snack(context, _isEdit ? 'Tenant updated' : 'Tenant added');
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rent = double.tryParse(_rent.text) ?? 0;
    final deposit = double.tryParse(_deposit.text) ?? 0;
    final due = rent + deposit; // first-month due includes the one-time deposit
    final paid = double.tryParse(_paid.text) ?? 0;
    final status = paid <= 0 ? '' : (paid < due ? 'Partial (₹${(due - paid).toStringAsFixed(0)} balance)' : 'Paid in full');

    return GradientScaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit tenant' : 'Add tenant')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              _photoSection(),
              const SizedBox(height: 12),
              _field(_name, 'Name'),
              const SizedBox(height: 12),
              _field(_phone, 'Phone', keyboard: TextInputType.phone),
              const SizedBox(height: 12),
              _field(_whatsapp, 'WhatsApp number', keyboard: TextInputType.phone),
              const SizedBox(height: 12),
              _field(_deposit, 'Deposit amount', keyboard: TextInputType.number, onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: Text('Join date: ${_fmt(_joinDate)}'),
                  trailing: const Icon(Icons.calendar_today, color: kBrown),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: _joinDate, firstDate: DateTime(2015), lastDate: DateTime(2100));
                    if (picked != null) setState(() => _joinDate = picked);
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (!_isEdit) ...[
                if (_vacant.isEmpty)
                  const Text('No vacant berths — tenant will be added without a berth.')
                else ...[
                  SearchableField<Map>(
                    label: 'Assign berth',
                    value: _berth,
                    items: _vacant.cast<Map>(),
                    labelOf: (b) => '${b['floor_name']}/${b['room_number']}/${b['label']} · ₹${b['rent']}',
                    onSelected: (b) => setState(() {
                      _berth = b;
                      _rent.text = '${b['rent']}'; // prefill default, editable
                    }),
                  ),
                  const SizedBox(height: 12),
                  _field(_rent, 'Monthly rent (editable)', keyboard: TextInputType.number, onChanged: (_) => setState(() {})),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('First month due (rent + deposit): ₹${due.toStringAsFixed(0)}', style: const TextStyle(color: kBrown, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                  _field(_paid, 'First payment (optional — partial or full)', keyboard: TextInputType.number, onChanged: (_) => setState(() {})),
                  if (status.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(status, style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600))),
                ],
              ] else ...[
                if (widget.tenant!['berth'] != null) ...[
                  _field(_rent, 'Monthly rent', keyboard: TextInputType.number),
                  const SizedBox(height: 12),
                ],
                const Text('To change room/berth, use Move on the tenant card.', style: TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 20),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              BusyButton(label: _isEdit ? 'Save changes' : 'Save tenant', onPressed: _save),
            ]),
    );
  }

  Widget _photoSection() {
    final img = photoProvider(_photo);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tenant file (ID / Aadhaar)', style: TextStyle(fontWeight: FontWeight.w600, color: kGreen)),
          const SizedBox(height: 10),
          Row(children: [
            GestureDetector(
              onTap: img != null ? () => viewImage(context, img) : null,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: kMint.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  image: img != null ? DecorationImage(image: img, fit: BoxFit.cover) : null,
                ),
                child: img == null ? const Icon(Icons.person, size: 40, color: kBrown) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.photo_camera, size: 18), label: const Text('Camera'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library, size: 18), label: const Text('Upload'))),
                ]),
                if (img != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _photo = ''),
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      label: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ),
              ]),
            ),
          ]),
          if (img != null)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Tap the file to view full size.', style: TextStyle(fontSize: 11, color: Colors.black45))),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {TextInputType? keyboard, ValueChanged<String>? onChanged}) =>
      TextField(
        controller: c,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), filled: true, fillColor: Colors.white),
      );
}
