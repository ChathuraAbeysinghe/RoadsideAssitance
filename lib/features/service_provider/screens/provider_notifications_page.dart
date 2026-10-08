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
      backgroundColor: const Color(0xfff8fafc),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Unable to load notifications.'));
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _brandRed),
            );
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No Notifications Yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We\'ll notify you when there\'s something new.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final n = list[i];
              return Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) {
                  _repo.deleteNotification(n.id).catchError((_) {});
                },
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.only(right: 20),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: n.requestId == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProviderJobPage(requestId: n.requestId!),
                              ),
                            ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _brandRed.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _iconFor(n.type),
                                color: _brandRed,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    n.body,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    formatWhen(n.createdAt),
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
