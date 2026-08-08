import 'package:flutter/material.dart';

class RoundStepButton extends StatelessWidget {
  final bool isAdd;
  final VoidCallback? onPressed;
  final double size;

  const RoundStepButton({
    super.key,
    required this.isAdd,
    required this.onPressed,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final background = isAdd
        ? const Color(0xFFE9DDFB)
        : const Color(0xFFFFE5E8);
    final foreground = isAdd ? const Color(0xFF17131D) : const Color(0xFFD92D32);

    return Opacity(
      opacity: onPressed == null ? .35 : 1,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              isAdd ? Icons.add_rounded : Icons.remove_rounded,
              color: foreground,
              size: size * .55,
            ),
          ),
        ),
      ),
    );
  }
}
