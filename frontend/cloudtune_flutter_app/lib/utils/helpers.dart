import 'package:flutter/material.dart';

class Helpers {
  // Show snackbar with message
  static void showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // Show dialog with title and message
  static Future<void> showDialogBox(
    BuildContext context,
    String title,
    String message, {
    String confirmText = 'OK',
    VoidCallback? onConfirmed,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              if (onConfirmed != null) {
                onConfirmed();
              }
              Navigator.of(context).pop();
            },
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }
}