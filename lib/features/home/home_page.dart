import 'dart:async';

import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({super.key, this.userName = 'Kavidu Purnamal'});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Add / remove image paths here — the carousel adapts to however many you put.
  final List<String> _heroImages = const [
    'assets/images/hero.png',
    'assets/images/autoshop.jpg',
    'assets/images/hero.png',
  ];

  late final PageController _heroController;
  Timer? _heroTimer;
  int _currentHeroPage = 0;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  void initState() {
    super.initState();
    _heroController = PageController(initialPage: 0);
    _startHeroTimer();
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || !_heroController.hasClients) return;
      _currentHeroPage = (_currentHeroPage + 1) % _heroImages.length;
      _heroController.animateToPage(
        _currentHeroPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Fixed header and search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color.fromARGB(84, 165, 164, 164),
                      ),
                    ),
                    child: Icon(
                      Icons.person_outline,
                      color: const Color.fromARGB(151, 117, 117, 117),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Hi ${widget.userName}\n$_greeting',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.notifications_none,
                    size: 26,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey.shade500),
                    const SizedBox(width: 10),
                    Text(
                      'Search Here',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              // ClipRRect (not just Container.clipBehavior) is what makes the
              // rounding visible on scroll: it clips based on this widget's
              // fixed bounds regardless of what's scrolling underneath, so
              // anything inside that touches these edges gets its corners
              // cut off in this shape as it scrolls past.
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Container(
                  color: Colors.white,
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 90),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Auto-rotating hero carousel (changes image every 5 seconds).
                            // Deliberately full-bleed (no side padding, no own
                            // ClipRRect) — it has to touch the sheet's top/left/
                            // right edges for the outer ClipRRect above to
                            // actually round its corners as it scrolls.
                            SizedBox(
                              height: 210,
                              width: double.infinity,
                              child: PageView.builder(
                                controller: _heroController,
                                itemCount: _heroImages.length,
                                onPageChanged: (index) {
                                  _currentHeroPage = index;
                                },
                                itemBuilder: (context, index) {
                                  return Image.asset(
                                    _heroImages[index],
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              color: const Color(0xFFE30613),
                                            ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Emergency Services section
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Emergency Services',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Row 1: two bigger cards
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Vehicle Tow',
                                          imagePath: 'assets/images/towing.png',
                                          height: 130,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Request Mechanic',
                                          imagePath:
                                              'assets/images/mechanic.png',
                                          height: 130,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Row 2: three smaller cards
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Request Fuel',
                                          imagePath:
                                              'assets/images/outoffuel.png',
                                          height: 80,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Flat Tire',
                                          imagePath:
                                              'assets/images/flattire.png',
                                          height: 80,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Jump Start',
                                          imagePath:
                                              'assets/images/jumpstart.png',
                                          height: 80,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bottom navigation bar overlays the scrollable content.
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: SafeArea(top: false, child: _BottomNavBar()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceItem extends StatelessWidget {
  final String label;
  final String imagePath;
  final double height;

  const _ServiceItem({
    required this.label,
    required this.imagePath,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              imagePath,
              height: height,
              width: double.infinity,
              fit: BoxFit.fitWidth,
              errorBuilder: (context, error, stackTrace) => Container(
                height: height,
                width: double.infinity,
                color: Colors.grey.shade300,
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
        children: const [
          _NavItem(
            label: 'Home',
            iconPath: 'assets/images/home1.png',
            isActive: true,
          ),
          _NavItem(label: 'Requests', iconPath: 'assets/images/clipboard1.png'),
          _NavItem(label: 'Vehicle', iconPath: 'assets/images/wheel1.png'),
          _NavItem(label: 'More', iconPath: 'assets/images/application1.png'),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final String iconPath;
  final bool isActive;

  const _NavItem({
    required this.label,
    required this.iconPath,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFFE30613) : Colors.grey.shade600;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          iconPath,
          height: 24,
          width: 24,
          color: color,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.circle_outlined, size: 24, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
