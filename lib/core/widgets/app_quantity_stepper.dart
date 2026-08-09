import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_spacing.dart';

/// A quantity control: [-] numeric-field [+]. The screen owns [controller];
/// [onChanged] fires with the parsed value on every change (button or typing).
class AppQuantityStepper extends StatelessWidget {
  const AppQuantityStepper({
    super.key,
    required this.controller,
    required this.onChanged,
    this.min = 1,
    this.step = 1,
  });

  final TextEditingController controller;
  final ValueChanged<int> onChanged;
  final int min;
  final int step;

  int get _current => int.tryParse(controller.text.trim()) ?? min;

  void _set(int value) {
    final v = value < min ? min : value;
    controller.text = '$v';
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _btn(Icons.remove, () => _set(_current - step)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => onChanged(int.tryParse(v.trim()) ?? min),
            ),
          ),
        ),
        _btn(Icons.add, () => _set(_current + step), filled: true),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap, {bool filled = false}) {
    return SizedBox(
      width: 48,
      height: 48,
      child: filled
          ? IconButton.filled(onPressed: onTap, icon: Icon(icon))
          : IconButton.outlined(onPressed: onTap, icon: Icon(icon)),
    );
  }
}
