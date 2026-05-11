import 'package:flutter/material.dart';

class AccessibleButton extends StatelessWidget {
  final String label;
  final String? hint;
  final VoidCallback onPressed;
  final Widget child;
  final double minHeight;

  const AccessibleButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    this.hint,
    this.minHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      hint: hint,
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: minHeight,
        child: ElevatedButton(
          onPressed: onPressed,
          child: child,
        ),
      ),
    );
  }
}
