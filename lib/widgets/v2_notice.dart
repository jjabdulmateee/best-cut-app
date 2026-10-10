import 'package:flutter/material.dart';

/// Same explanation for every Settings / Account action that is not in this release.
void showV2Notice(BuildContext context, String feature) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(feature),
      content: Text(
        '$feature is scheduled for V2 and will be available in a later release.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
