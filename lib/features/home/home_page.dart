import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../_share/navbar/app_bottom_nav_bar.dart';
import '../vehicles/vehicle_list_page.dart';

class HomePage extends StatefulWidget {
  final String userName;
  final String profileImagePath;

  const HomePage({
    super.key,
    this.userName = 'Driver',
    this.profileImagePath = '',
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Add / remove image paths here — the carousel adapts to however many you put.
  final List<String> _heroImages = const [
    'assets/images/fuelstation.jpg',
    'assets/images/autoshop.jpg',
  ];

  late final PageController _heroController;
  Timer? _heroTimer;
  int _currentHeroPage = 0;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning!';
    if (hour < 17) return 'Good Afternoon!';
    return 'Good Evening!';
  }

  @override
  void initState() {
    super.initState();
    _heroController = PageController(initialPage: 0);
    _startHeroTimer();
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || !_heroController.hasClients) return;
      _currentHeroPage = (_currentHeroPage + 1) % _heroImages.length;
      _heroController.animateToPage(
        _currentHeroPage,
        duration: const Duration(milliseconds: 10),
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

  // Nav bar indices: 0 = Home, 1 = Requests, 2 = Vehicle, 3 = More.
  void _onNavTap(int index) {
    switch (index) {
      case 0:
        // Already on Home — nothing to do.
        break;
      case 2:
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => VehicleListPage(uid: uid)));
        break;
      case 1:
      case 3:
      default:
        // TODO: replace with real Requests / More pages once they
        // exist. Routed to HomePage as a placeholder for now.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HomePage(
              userName: widget.userName,
              profileImagePath: widget.profileImagePath,
            ),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.centerRight,
            colors: [
              Color.fromARGB(255, 255, 195, 66),
              Color.fromARGB(255, 255, 240, 153),
            ],
          ),
        ),
        child: SafeArea(
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
                          color: const Color.fromARGB(0, 212, 211, 211),
                        ),
                      ),
                      child: ClipOval(
                        child: widget.profileImagePath.isEmpty
                            ? Image.asset(
                                'assets/images/profile.png',
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                widget.profileImagePath,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Image.asset(
                                      'assets/images/profile.png',
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    ),
                              ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Hi ${widget.userName},\n$_greeting',
                          style: const TextStyle(
                            fontSize: 15,

                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: Color.fromARGB(255, 0, 0, 0),
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
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(40),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 15,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 5),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                              child: Container(
                                height: 52,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'What service do you need?',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Emergency Services section
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Row 1: two bigger cards
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Vehicle Tow',
                                          imagePath: 'assets/images/towing.png',
                                          height: 110,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Request Mechanic',
                                          imagePath:
                                              'assets/images/mechanic.png',
                                          height: 110,
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
                                          height: 60,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Flat Tire',
                                          imagePath:
                                              'assets/images/flattire.png',
                                          height: 60,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Jump Start',
                                          imagePath:
                                              'assets/images/jumpstart.png',
                                          height: 60,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: const [
                                    SizedBox(height: 6),

                                    Text(
                                      'Explore Other Services',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Auto-rotating hero carousel (changes image every 5 seconds).
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SizedBox(
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
                                                    color: const Color(
                                                      0xFFE30613,
                                                    ),
                                                  ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),

                      // Bottom navigation bar overlays the scrollable content.
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: AppBottomNavBar(
                          activeIndex: 0,
                          items: const [
                            NavBarItem(
                              label: 'Home',
                              iconAssetPath: 'assets/images/home2.png',
                            ),
                            NavBarItem(
                              label: 'Requests',
                              iconAssetPath: 'assets/images/clipboard1.png',
                            ),
                            NavBarItem(
                              label: 'Vehicle',
                              iconAssetPath: 'assets/images/wheel1.png',
                            ),
                            NavBarItem(
                              label: 'More',
                              iconAssetPath: 'assets/images/application1.png',
                            ),
                          ],
                          onTap: _onNavTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
