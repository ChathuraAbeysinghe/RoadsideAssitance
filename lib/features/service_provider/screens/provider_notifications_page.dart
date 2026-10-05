import 'package:flutter/material.dart';

import '../services/provider_repository.dart';
import 'provider_job_page.dart';
import 'provider_ui_helpers.dart';

const Color _brandRed = Color(0xFFE30613);

class ProviderNotificationsPage extends StatefulWidget {
  final String uid;
  const ProviderNotificationsPage({super.key, required this.uid});

  @override
  State<ProviderNotificationsPage> createState() =>
      _ProviderNotificationsPageState();
}

class _ProviderNotificationsPageState extends State<ProviderNotificationsPage> {
  final _repo = ProviderRepository();
  late final Stream<List<AppNotification>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _repo.watchNotifications(widget.uid);
    // Opening the page marks everything as read (badge on the bell clears).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo.markAllRead(widget.uid).catchError((_) {});
    });
  }

  IconData _iconFor(String type) => switch (type) {
    'accepted' => Icons.check_circle_outline,
    'completed' => Icons.verified_outlined,
    'cancelled' => Icons.cancel_outlined,
    'newRequest' => Icons.notifications_active_outlined,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Unable to load notifications.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none,
                      size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, i) {
              final n = list[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: CircleAvatar(
                  backgroundColor: _brandRed.withValues(alpha: 0.1),
                  child: Icon(_iconFor(n.type), color: _brandRed),
                ),
                title: Text(
                  n.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${n.body}\n${formatWhen(n.createdAt)}'),
                isThreeLine: true,
                onTap: n.requestId == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProviderJobPage(requestId: n.requestId!),
                        ),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
