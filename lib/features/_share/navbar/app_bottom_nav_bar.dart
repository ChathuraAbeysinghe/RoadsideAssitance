import 'package:flutter/material.dart';

/// One item in the shared [AppBottomNavBar].
///
/// Supports either an image asset icon (with an optional [activeColor]
/// override — pass null to show the image's own colors when active, as
/// the driver home page's icons currently do) or a Material [IconData]
/// icon, so both the driver and provider nav bars can share one widget.
class NavBarItem {
  final String label;
  final String? iconAssetPath;
  final IconData? iconData;

  const NavBarItem({
    required this.label,
    this.iconAssetPath,
    this.iconData,
  }) : assert(
          iconAssetPath != null || iconData != null,
          'Provide either iconAssetPath or iconData',
        );
}

/// Shared bottom navigation bar shell used across driver and provider
/// pages. Pass the four [items] for the current role and which [activeIndex]
/// is selected; [onTap] fires with the tapped index.
///
/// Usage:
/// ```dart
/// AppBottomNavBar(
///   activeIndex: 0,
///   items: const [
///     NavBarItem(label: 'Home', iconAssetPath: 'assets/images/home2.png'),
///     NavBarItem(label: 'Requests', iconAssetPath: 'assets/images/clipboard1.png'),
///     NavBarItem(label: 'Vehicle', iconAssetPath: 'assets/images/wheel1.png'),
///     NavBarItem(label: 'More', iconAssetPath: 'assets/images/application1.png'),
///   ],
///   onTap: (index) { /* navigate */ },
/// )
/// ```
class AppBottomNavBar extends StatelessWidget {
  final List<NavBarItem> items;
  final int activeIndex;
  final ValueChanged<int>? onTap;

  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.activeIndex,
    this.onTap,
  });

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
        children: List.generate(items.length, (index) {
          return _NavItem(
            item: items[index],
            isActive: index == activeIndex,
            onTap: onTap == null ? null : () => onTap!(index),
          );
        }),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavBarItem item;
  final bool isActive;
  final VoidCallback? onTap;

  const _NavItem({required this.item, required this.isActive, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.black : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (item.iconAssetPath != null)
            Image.asset(
              item.iconAssetPath!,
              height: 24,
              width: 24,
              // Matches the driver HomePage's original behavior: the
              // active tab shows the asset's own colors (no tint),
              // inactive tabs are tinted grey.
              color: isActive ? null : Colors.grey.shade600,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.circle_outlined, size: 24, color: color),
            )
          else
            Icon(item.iconData, size: 24, color: color),
          const SizedBox(height: 4),
          Text(
            item.label,
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
