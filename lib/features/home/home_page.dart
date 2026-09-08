import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  final String userName;

  const HomePage({super.key, this.userName = 'Kavidu Purnamal'});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Fixed greeting header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Hi $userName,\n$_greeting',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                  ),
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
                ],
              ),
            ),

            // Keep the hero behind the scrollable service sheet.
            Expanded(
              child: Stack(
                children: [
                  SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: Image.asset(
                      'assets/images/hero.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: const Color(0xFFE30613)),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    bottom: 36,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '24/7 Roadside Assistance',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 255, 254, 254),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Anywhere Across the Island',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: -1,
                    left: 0,
                    right: 0,
                    child: ClipPath(
                      clipper: _CurveClipper(),
                      child: Container(height: 28, color: Colors.white),
                    ),
                  ),
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 190),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 14,
                                offset: Offset(0, -4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),

                              // "What do you need help with?" section
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
                                            label: 'Car Towing',
                                            imagePath:
                                                'assets/images/towing.jpg',
                                            height: 150,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: _ServiceItem(
                                            label: 'Request Mechanic',
                                            imagePath:
                                                'assets/images/mechanic.png',
                                            height: 150,
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
                                            label: 'Out of Gas',
                                            imagePath:
                                                'assets/images/outoffuel.jpg',
                                            height: 110,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _ServiceItem(
                                            label: 'Dead Battery',
                                            imagePath:
                                                'assets/images/jumpstart.jpg',
                                            height: 110,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _ServiceItem(
                                            label: 'Flat Tire',
                                            imagePath:
                                                'assets/images/flattire.png',
                                            height: 110,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 32),

                                    const Text(
                                      'Explore Nearby',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.asset(
                                        'assets/images/hero.png',
                                        height: 130,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  height: 130,
                                                  color: Colors.grey.shade300,
                                                ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom navigation bar
            SafeArea(top: false, child: _BottomNavBar()),
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
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            imagePath,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
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
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
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

/// Creates a gentle upward curve on the bottom edge of the hero banner,
/// so the white section below blends smoothly into the image.
class _CurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width / 2,
      size.height * 1.4,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
