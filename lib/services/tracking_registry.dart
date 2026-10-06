/// Remembers which requests have a tracking page open (or had one this
/// session), so the same job is never opened twice.
///
/// Both tracking pages call [add] in initState and [remove] in dispose, and
/// IncomingRequestListener checks it before opening a page automatically.
class TrackingRegistry {
  TrackingRegistry._();

  static final Set<String> _open = {};
  static final Set<String> _seen = {};

  /// A tracking page for this request is on screen right now.
  static bool isOpen(String requestId) => _open.contains(requestId);

  /// A tracking page for this request has been shown at some point this
  /// session (so don't force it open again after the user left it).
  static bool wasOpened(String requestId) => _seen.contains(requestId);

  static void add(String requestId) {
    _open.add(requestId);
    _seen.add(requestId);
  }

  static void remove(String requestId) => _open.remove(requestId);

  /// Called on logout.
  static void clear() {
    _open.clear();
    _seen.clear();
  }
}
