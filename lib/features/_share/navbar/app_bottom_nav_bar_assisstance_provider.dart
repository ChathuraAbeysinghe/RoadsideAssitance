import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../vehicles/vehicle_list_page.dart';
import '../../home/assistance_provider_home_page.dart';

/// One tab in [AppBottomNavBarAssisstanceProvider]. Fully internal now —
/// hosting pages never construct these; see [AppBottomNavBarAssisstanceProvider._tabs].
class _NavTab {
  final String label;
  final String iconAssetPath;
  final WidgetBuilder destinationBuilder;

  const _NavTab({
    required this.label,
    required this.iconAssetPath,
    required this.destinationBuilder,
  });
}

/// Bottom navigation bar shell for assistance-provider pages (mechanic, tow
/// truck, fuel delivery, flat tire, battery boost). Owns its own routing:
/// the four tabs and where each one navigates are defined once, right here
/// — no page that shows this nav bar needs to build an item list, wire up
/// an `onTap` switch statement, or pass down a uid.
///
/// The signed-in user's uid (needed by tabs like `VehicleListPage`) is read
/// directly from `FirebaseAuth.instance.currentUser` — see [_uid].
///
/// Usage — every page just says which tab it corresponds to:
/// ```dart
/// // On AssistanceProviderHomePage's build():
/// const AppBottomNavBarAssisstanceProvider(activeIndex: 0),
///
/// // On VehicleListPage's build():
/// const AppBottomNavBarAssisstanceProvider(activeIndex: 2),
/// ```
///
/// Tapping the already-active tab does nothing (no duplicate page push).
/// Tapping any other tab pushes that tab's page on top of the current one
/// via `Navigator.push`, so the back button returns to where you were.
///
/// To change where a tab goes, edit [_tabs] below — nowhere else.
class AppBottomNavBarAssisstanceProvider extends StatelessWidget {
  final int activeIndex;

  const AppBottomNavBarAssisstanceProvider({
    super.key,
    required this.activeIndex,
  });

  // Currently signed-in user's uid, read directly from FirebaseAuth so no
  // hosting page needs to thread it through. Empty if no one is signed in
  // (shouldn't normally happen on an authenticated screen, but _handleTap
  // guards against it below rather than crashing on a null uid).
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Single source of truth for every tab: label, icon, and destination.
  // TEMP: Job and More both point at AssistanceProviderHomePage until their
  // real pages exist — swap those two builders when ready.
  List<_NavTab> get _tabs => [
    _NavTab(
      label: 'Home',
      iconAssetPath: 'assets/images/home2.png',
      destinationBuilder: (_) => const AssistanceProviderHomePage(),
    ),
    _NavTab(
      label: 'Job',
      iconAssetPath: 'assets/images/clipboard1.png',
      destinationBuilder: (_) => const AssistanceProviderHomePage(), // TEMP
    ),
    _NavTab(
      label: 'Vehicle',
      iconAssetPath: 'assets/images/wheel1.png',
      destinationBuilder: (_) => VehicleListPage(uid: _uid),
    ),
    _NavTab(
      label: 'More',
      iconAssetPath: 'assets/images/application1.png',
      destinationBuilder: (_) => const AssistanceProviderHomePage(), // TEMP
    ),
  ];

  void _handleTap(BuildContext context, int index) {
    if (index == activeIndex) return; // already on this tab — no-op

    if (_uid.isEmpty) {
      // TODO: decide how you want to handle a missing session here —
      // e.g. route to a sign-in page instead of showing this message.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again to continue.')),
      );
      return;
    }

    Navigator.of(context)
        .push(MaterialPageRoute(builder: _tabs[index].destinationBuilder));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      width: double.infinity,
      height: 86 + bottomInset,
      padding: EdgeInsets.only(top: 10, bottom: bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(_tabs.length, (index) {
          return _NavItem(
            tab: _tabs[index],
            isActive: index == activeIndex,
            onTap: () => _handleTap(context, index),
          );
        }),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _NavTab tab;
  final bool isActive;
  final VoidCallback? onTap;

  const _NavItem({required this.tab, required this.isActive, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.black : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            tab.iconAssetPath,
            height: 24,
            width: 24,
            // Matches the driver HomePage's original behavior: the
            // active tab shows the asset's own colors (no tint),
            // inactive tabs are tinted grey.
            color: isActive ? null : Colors.grey.shade600,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.circle_outlined, size: 24, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            tab.label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
