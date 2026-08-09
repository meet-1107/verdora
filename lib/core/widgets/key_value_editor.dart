import 'package:flutter/material.dart';

/// A dynamic list of key/value rows, used for product & variant attributes
/// (Size, Color, Material, Voltage…). Emits the current entries via [onChanged].
class KeyValueEditor extends StatefulWidget {
  const KeyValueEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.title = 'Attributes',
    this.keyHint = 'Attribute',
    this.valueHint = 'Value',
  });

  final List<MapEntry<String, String>> initial;
  final ValueChanged<List<MapEntry<String, String>>> onChanged;
  final String title;
  final String keyHint;
  final String valueHint;

  @override
  State<KeyValueEditor> createState() => _KeyValueEditorState();
}

class _KeyValueEditorState extends State<KeyValueEditor> {
  late final List<_Row> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.initial
        .map((e) => _Row(
              key: TextEditingController(text: e.key),
              value: TextEditingController(text: e.value),
            ))
        .toList();
    if (_rows.isEmpty) _rows.add(_Row.empty());
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.key.dispose();
      r.value.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final entries = <MapEntry<String, String>>[];
    for (final r in _rows) {
      final k = r.key.text.trim();
      if (k.isEmpty) continue;
      entries.add(MapEntry(k, r.value.text.trim()));
    }
    widget.onChanged(entries);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_Row.empty())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rows[i].key,
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.keyHint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _rows[i].value,
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.valueHint,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _rows.length == 1
                      ? null
                      : () {
                          setState(() {
                            _rows[i].key.dispose();
                            _rows[i].value.dispose();
                            _rows.removeAt(i);
                          });
                          _emit();
                        },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Row {
  _Row({required this.key, required this.value});
  factory _Row.empty() =>
      _Row(key: TextEditingController(), value: TextEditingController());
  final TextEditingController key;
  final TextEditingController value;
}
