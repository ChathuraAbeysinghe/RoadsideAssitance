import 'package:flutter/material.dart';

import '../../../entities/service_request.dart';

String money(double v) => 'Rs ${v.toStringAsFixed(2)}';

String formatWhen(DateTime? d) {
  if (d == null) return '-';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]}, $hh:$mm';
}

String statusLabel(RequestStatus s) => switch (s) {
  RequestStatus.pending => 'Pending',
  RequestStatus.accepted => 'Accepted',
  RequestStatus.onTheWay => 'On the way',
  RequestStatus.arrived => 'Arrived',
  RequestStatus.inProgress => 'In progress',
  RequestStatus.completed => 'Completed',
  RequestStatus.cancelled => 'Cancelled',
  RequestStatus.expired => 'Expired',
};

Color statusColor(RequestStatus s) => switch (s) {
  RequestStatus.completed => Colors.green,
  RequestStatus.cancelled || RequestStatus.expired => Colors.grey,
  RequestStatus.pending => Colors.orange,
  _ => const Color(0xFF1B7F9E),
};

bool isToday(DateTime? d) {
  if (d == null) return false;
  final n = DateTime.now();
  return d.year == n.year && d.month == n.month && d.day == n.day;
}
