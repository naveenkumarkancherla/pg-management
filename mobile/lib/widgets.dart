import 'package:flutter/material.dart';

import 'theme.dart';

/// FutureBuilder with consistent loading spinner, error+retry, and data states.
class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final VoidCallback? onRetry;
  const AsyncView({super.key, required this.future, required this.builder, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('${snap.error}', textAlign: TextAlign.center),
              ),
              if (onRetry != null)
                FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ]),
          );
        }
        return builder(c, snap.data as T);
      },
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  const StatCard({super.key, required this.label, required this.value, this.sub, this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 15, color: kBrown), const SizedBox(width: 5)],
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          ]),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kGreen)),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 10, color: Colors.black45)),
        ]),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const SectionCard({super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: kBrown),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kGreen)),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  const KeyValueRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Small helper to show a snackbar.
void snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// Runs an async mutation behind a blocking loader, then shows a success or
/// error snackbar. Returns true on success (caller then re-fetches its data).
Future<bool> runTask(BuildContext context, Future<void> Function() task, {String? success}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    await task();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted && success != null) snack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) snack(context, '$e');
    return false;
  }
}

/// A dropdown-style field that opens a searchable picker dialog.
class SearchableField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  const SearchableField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onSelected,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (_) => _SearchDialog<T>(title: label, items: items, labelOf: labelOf),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: items.isEmpty ? null : () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          value != null ? labelOf(value as T) : 'Select',
          style: TextStyle(color: value != null ? null : Colors.black45),
        ),
      ),
    );
  }
}

/// Opens the searchable picker directly and returns the chosen item (or null).
Future<T?> pickItem<T>(BuildContext context,
        {required String title, required List<T> items, required String Function(T) labelOf}) =>
    showDialog<T>(context: context, builder: (_) => _SearchDialog<T>(title: title, items: items, labelOf: labelOf));

class _SearchDialog<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  const _SearchDialog({required this.title, required this.items, required this.labelOf});
  @override
  State<_SearchDialog<T>> createState() => _SearchDialogState<T>();
}

class _SearchDialogState<T> extends State<_SearchDialog<T>> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((i) => widget.labelOf(i).toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final i in filtered)
                ListTile(dense: true, title: Text(widget.labelOf(i)), onTap: () => Navigator.pop(context, i)),
              if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No matches')),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// FilledButton that shows a spinner while [onPressed] runs.
class BusyButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  const BusyButton({super.key, required this.label, required this.onPressed});
  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onPressed();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: _busy
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(widget.label),
    );
  }
}
