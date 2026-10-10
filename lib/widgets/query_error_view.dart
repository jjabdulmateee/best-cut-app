import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Friendly fallback UI for failed Firestore streams / futures.
///
/// Maps common backend failures (missing composite index, permission denied,
/// offline) to plain-language copy so users never see a raw exception or a
/// red error screen. The technical detail is only printed to the console.
class QueryErrorView extends StatelessWidget {
  final Object? error;
  final String title;
  final VoidCallback? onRetry;
  final bool compact;

  const QueryErrorView({
    super.key,
    required this.error,
    this.title = 'Something went wrong',
    this.onRetry,
    this.compact = false,
  });

  /// Human-readable explanation for [error].
  static String friendlyMessage(Object? error) {
    final code = error is FirebaseException ? error.code : '';
    final text = error?.toString().toLowerCase() ?? '';

    if (code == 'failed-precondition' || text.contains('requires an index')) {
      return 'This feature is still being set up on our servers. '
          'Please try again in a few minutes.';
    }
    if (code == 'permission-denied' || text.contains('permission')) {
      return 'You don\'t have access to this information right now. '
          'Try signing out and back in.';
    }
    if (code == 'unavailable' ||
        text.contains('unavailable') ||
        text.contains('network') ||
        text.contains('offline')) {
      return 'We couldn\'t reach the server. '
          'Please check your internet connection and try again.';
    }
    if (text.contains('null') || text.contains('type \'') || text.contains('is not a subtype')) {
      return 'Some of this information couldn\'t be read. '
          'Please try again — if it keeps happening, contact support.';
    }
    return 'We couldn\'t load this right now. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('⚠️ QueryErrorView: $error');
    final message = friendlyMessage(error);

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.orange[700], size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.orange[800], fontSize: 13),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Retry'),
              ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.cloud_off_rounded,
                  color: Colors.orange[700], size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A1A1A),
                  side: const BorderSide(color: Color(0xFF1A1A1A)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
