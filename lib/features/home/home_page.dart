import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../entities/app_user.dart';
import '../_share/navbar/app_bottom_nav_bar.dart';
import '../request_service/request_service.dart';

class HomePage extends StatefulWidget {
  final UserType userType;

  const HomePage({super.key, this.userType = UserType.driver});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Set to false if hero.png already contains the "24/7 Roadside Assistance" text.
  static const bool _showHeroText = true;

  // Add / remove image paths here — the carousel adapts to however many you put.
  final List<String> _heroImages = const [
    'assets/images/fuelstation.jpg',
    'assets/images/autoshop.jpg',
  ];

  late final PageController _heroController;
  late final Future<AppUser?> _userFuture;
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
    _userFuture = _loadCurrentUser();
    _heroController = PageController(initialPage: 0);
    _startHeroTimer();
  }

  Future<AppUser?> _loadCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final document = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = document.data();
    if (!document.exists || data == null) return null;
    return userFromMap(uid, data);
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

  void _openService(ServiceType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RequestServicePage(serviceType: type, userType: widget.userType),
      ),
    );
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  Widget _buildHeader() {
    return FutureBuilder<AppUser?>(
      future: _userFuture,
      builder: (context, snapshot) {
        final appUser = snapshot.data;
        final userName = appUser?.name.trim().isNotEmpty == true
            ? appUser!.name
            : 'Driver';
        final profileImagePath = appUser?.profileImagePath ?? '';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color.fromARGB(255, 196, 196, 196),
                  ),
                ),
                child: ClipOval(
                  child: profileImagePath.isEmpty
                      ? Image.asset(
                          'assets/images/profile.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          profileImagePath,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Icon(
                Icons.notifications_none,
                size: 26,
                color: Colors.black87,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroTextOverlay() {
    const shadows = [
      Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
    ];
    return const Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        // Lower this number to push the text further down, raise it to move it up.
        padding: EdgeInsets.only(bottom: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '24/7 Roadside Assistance',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                shadows: shadows,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Anywhere Across the Island',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    const headerContentHeight = 72.0; // avatar row area
    const heroTextAreaHeight = 120.0; // visible hero height above white card
    const heroOverlap = 50.0; // hero image extends behind the card corners
    const heroRaise = 20.0; // how much higher the hero image starts

    final headerHeight = topInset + headerContentHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Hero image (red banner) starts higher (behind the header row)
          // and extends behind the rounded top of the white card.
          Positioned(
            top: headerHeight - heroRaise,
            left: 0,
            right: 0,
            height: heroTextAreaHeight + heroOverlap + heroRaise,
            child: Image.asset(
              'assets/images/hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFFE30613)),
            ),
          ),

          Column(
            children: [
              // Header (avatar, greeting, bell)
              SizedBox(
                height: headerHeight,
                child: Padding(
                  padding: EdgeInsets.only(top: topInset),
                  child: Align(
                    alignment: Alignment.center,
                    child: _buildHeader(),
                  ),
                ),
              ),

              // Hero title text area
              SizedBox(
                height: heroTextAreaHeight,
                width: double.infinity,
                child: _showHeroText ? _buildHeroTextOverlay() : null,
              ),

              // White rounded content card
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
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 25, 20, 0),
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
                                      'What service do you need ?',
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
                                          onTap: () => _openService(
                                            ServiceType.towTruck,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Request Mechanic',
                                          imagePath:
                                              'assets/images/mechanic.png',
                                          height: 110,
                                          onTap: () => _openService(
                                            ServiceType.mechanic,
                                          ),
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
                                          label: 'Jump Start',
                                          imagePath:
                                              'assets/images/jumpstart.png',
                                          height: 60,
                                          onTap: () => _openService(
                                            ServiceType.batteryBoost,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Flat Tire',
                                          imagePath:
                                              'assets/images/flattire.png',
                                          height: 60,
                                          onTap: () => _openService(
                                            ServiceType.flatTireChange,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ServiceItem(
                                          label: 'Fuel Delivery',
                                          imagePath:
                                              'assets/images/outoffuel.png',
                                          height: 60,
                                          onTap: () => _openService(
                                            ServiceType.fuelDelivery,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(height: 6),
                                    Text(
                                      'Explore Nearby',
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

                            // Auto-rotating carousel
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
                          userType: widget.userType,
                          activeIndex: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceItem extends StatelessWidget {
  final String label;
  final String imagePath;
  final double height;
  final VoidCallback onTap;

  const _ServiceItem({
    required this.label,
    required this.imagePath,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
      ),
    );
  }
}
