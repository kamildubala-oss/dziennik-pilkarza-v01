import 'package:flutter/material.dart';

import '../models.dart';
import '../services/user_errors.dart';
import 'activity_editor.dart';

/// Zgodność ze starszymi wywołaniami; używa wspólnego formularza treningu.
class ClubTrainingScreen extends StatefulWidget {
  const ClubTrainingScreen({super.key, required this.event});
  final EventItem event;

  @override
  State<ClubTrainingScreen> createState() => _ClubTrainingScreenState();
}

class _ClubTrainingScreenState extends State<ClubTrainingScreen> {
  late final Future<Widget> _page = activityEditor(widget.event, complete: true);

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: _page,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(appBar: AppBar(title: const Text('Trening klubowy')),
          body: Center(child: Text(friendlyError(snapshot.error!))));
      }
      return snapshot.data ?? const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    },
  );
}
