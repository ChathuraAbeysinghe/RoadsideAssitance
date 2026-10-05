import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../entities/app_user.dart';
import '../../main.dart';
import '../_share/navbar/app_bottom_nav_bar.dart';
import '../profile/profile_page.dart';

const Color _brandRed = Color(0xFFE30613);

// TODO: replace with your real support details.
const String _supportEmail = 'support@example.com';
const String _supportPhone = '+94 11 000 0000';

/// "More" screen: profile, privacy policy, contact us, report, log out.
/// Shared by both roles; [userType] only decides which navbar tabs show.
class MorePage extends StatelessWidget {
  final UserType userType;

  const MorePage({super.key, required this.userType});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to use the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out', style: TextStyle(color: _brandRed)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final auth = FirebaseAuth.instance;
    final uid = auth.currentUser?.uid;

    // Providers stop showing on customers' maps once they log out.
    if (uid != null) {
      try {
        final ref = FirebaseFirestore.instance.collection('users').doc(uid);
        final snap = await ref.get();
        if (snap.data()?['userType'] == UserType.assistanceProvider.name) {
          await ref.update({'isAvailable': false});
        }
      } catch (_) {}
    }

    try {
      await auth.signOut();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not log out')));
      }
      return;
    }
    if (!context.mounted) return;
    // Back to the root route (AuthGate), clearing all other routes.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  void _showContact(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Contact us',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a detail to copy it.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              _contactRow(
                ctx,
                icon: Icons.mail_outline,
                label: 'Email',
                value: _supportEmail,
              ),
              _contactRow(
                ctx,
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: _supportPhone,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$label copied')));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade700),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy, size: 18, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

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
          'More',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _ProfileHeader(onTap: () => _open(context, const ProfilePage())),
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade200),
            _MoreTile(
              icon: Icons.person_outline,
              title: 'Profile',
              onTap: () => _open(context, const ProfilePage()),
            ),
            _MoreTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () => _open(context, const PrivacyPolicyPage()),
            ),
            _MoreTile(
              icon: Icons.description_outlined,
              title: 'Terms & Conditions',
              onTap: () => _open(context, const TermsPage()),
            ),
            _MoreTile(
              icon: Icons.headset_mic_outlined,
              title: 'Contact Us',
              onTap: () => _showContact(context),
            ),
            _MoreTile(
              icon: Icons.flag_outlined,
              title: 'Report',
              onTap: () => _open(context, const ReportPage()),
            ),
            const SizedBox(height: 12),
            _MoreTile(
              icon: Icons.logout,
              title: 'Log out',
              color: _brandRed,
              showChevron: false,
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        userType: userType,
        activeIndex: 3, // "More" is the 4th tab
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;
  final bool showChevron;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Colors.black87;
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            child: Row(
              children: [
                Icon(icon, size: 24, color: fg),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (showChevron)
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade200),
      ],
    );
  }
}

/// Photo, name and phone number of the signed-in user, shown at the top of
/// the More page. Listens to the user doc so it updates right after the
/// profile is edited. Tapping it opens the profile page.
class _ProfileHeader extends StatelessWidget {
  final VoidCallback onTap;

  const _ProfileHeader({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final user = data == null ? null : userFromMap(uid, data);

        final name = user?.name ?? '';
        final phone = user?.phoneNumber ?? '';
        final photo = user?.profileImagePath ?? '';

        final fallback = ColoredBox(
          color: Colors.grey.shade200,
          child: Icon(Icons.person, size: 48, color: Colors.grey.shade500),
        );

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: ClipOval(
                    child: photo.isNotEmpty
                        ? Image.network(
                            photo,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => fallback,
                            loadingBuilder: (context, child, progress) =>
                                progress == null ? child : fallback,
                          )
                        : fallback,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  name.isEmpty ? 'Your name' : name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// Legal pages (Privacy Policy + Terms & Conditions)
// ============================================================

const String _legalUpdated = 'Last updated: October 2026';

/// PLACEHOLDER TEXT. Replace [Company Name] / contact details and have a
/// lawyer review both documents before publishing the app.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _intro =
      'This Privacy Policy explains what personal information the app '
      'collects, why we collect it, who we share it with and the choices '
      'you have. By creating an account and using the app you agree to '
      'the practices described here.';

  static const List<(String, String)> _sections = [
    (
      '1. Who we are',
      'The app connects drivers who need roadside assistance with nearby '
          'assistance providers. [Company Name] ("we", "us") is responsible '
          'for the personal information described in this policy.',
    ),
    (
      '2. Information we collect',
      'Account information: your name, mobile phone number, profile photo '
          'and whether you are a driver or an assistance provider.\n\n'
          'Provider information: the services you offer and your '
          'availability status.\n\n'
          'Vehicle information: for drivers, the make, model, type and plate '
          'number of the vehicles you add and which one is active.\n\n'
          'Request information: the type of assistance requested, the '
          'request status and history, and ratings given or received.\n\n'
          'Location information: your device location when you make a '
          'request, and a provider\'s live location while marked available.\n\n'
          'Reports and support: messages you send through the Report and '
          'Contact Us features.\n\n'
          'Technical information: basic device and app data needed to keep '
          'the service running and to diagnose errors.',
    ),
    (
      '3. How we use your information',
      '- To create and secure your account and verify your phone number.\n'
          '- To match drivers with nearby providers and show requests and '
          'their progress.\n'
          '- To let drivers and providers contact each other once a request '
          'is accepted.\n'
          '- To calculate and display ratings.\n'
          '- To investigate reports, prevent fraud and abuse, and keep the '
          'community safe.\n'
          '- To maintain, fix and improve the app.\n'
          '- To comply with legal obligations.',
    ),
    (
      '4. Location data',
      'Drivers share their location only when making a request. Providers '
          'share their live location while they are marked as available, and '
          'stop being shown on customers\' maps when they turn availability '
          'off or log out. You can disable location permission in your device '
          'settings at any time, but the app cannot match you with '
          'assistance without it. We do not track your location when you are '
          'not using the relevant features.',
    ),
    (
      '5. Who can see your information',
      'Other users: when a request is accepted, the driver and the provider '
          'can see each other\'s name, profile photo, rating and phone number. '
          'Providers who are available are visible to nearby drivers.\n\n'
          'Service providers: we use trusted third parties to run the app, '
          'including Google Firebase (authentication and database) and '
          'Cloudinary (profile photo storage). They process data only on '
          'our behalf.\n\n'
          'Legal and safety: we may disclose information if required by law, '
          'to respond to lawful requests from authorities, or to protect the '
          'safety and rights of users and the public.\n\n'
          'We do not sell your personal information.',
    ),
    (
      '6. How long we keep it',
      'We keep your information while your account is active. Request '
          'history and reports may be kept for a reasonable period afterwards '
          'for safety, dispute resolution and legal purposes. When data is no '
          'longer needed we delete it or anonymise it.',
    ),
    (
      '7. Security',
      'We use industry-standard safeguards, including encrypted connections '
          'and access controls, to protect your information. No system is '
          'completely secure, so we cannot guarantee absolute security. '
          'Please keep your login details private and tell us immediately if '
          'you suspect unauthorised access.',
    ),
    (
      '8. Your rights and choices',
      'Subject to applicable law, including Sri Lanka\'s Personal Data '
          'Protection Act, you may request access to, correction of, or '
          'deletion of your personal information, and may withdraw consent '
          'to its processing.\n\n'
          'You can update your name and photo from the Profile page. Your '
          'phone number is your login identifier and can only be changed by '
          'contacting us. To delete your account or exercise any other '
          'right, contact us using the details below.',
    ),
    (
      '9. Children',
      'The app is intended for people who are old enough to hold a driving '
          'licence or lawfully offer assistance services. It is not directed '
          'at children under 18 and we do not knowingly collect their '
          'information.',
    ),
    (
      '10. Changes to this policy',
      'We may update this policy from time to time. If we make significant '
          'changes we will notify you in the app. Continued use of the app '
          'after an update means you accept the revised policy.',
    ),
    (
      '11. Contact us',
      'Questions or requests about your data? Email $_supportEmail or call '
          '$_supportPhone.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentPage(
      title: 'Privacy Policy',
      intro: _intro,
      sections: _sections,
    );
  }
}

/// PLACEHOLDER TEXT. Have a lawyer review before publishing.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static const String _intro =
      'Please read these Terms & Conditions carefully. By creating an '
      'account or using the app you agree to be bound by them. If you do '
      'not agree, do not use the app.';

  static const List<(String, String)> _sections = [
    (
      '1. About the service',
      'The app is a platform that connects drivers who need roadside '
          'assistance (such as towing, battery jump-start, fuel delivery or '
          'tyre help) with independent assistance providers. We do not '
          'ourselves perform repairs or recovery and we are not a party to '
          'the agreement between a driver and a provider.',
    ),
    (
      '2. Eligibility and accounts',
      'You must be at least 18 years old and able to enter a binding '
          'contract. You agree to give accurate information, keep your login '
          'details secure and be responsible for all activity under your '
          'account. One person may not hold multiple accounts to evade '
          'suspension or manipulate ratings.',
    ),
    (
      '3. Driver responsibilities',
      '- Provide an accurate location, vehicle details and description of '
          'the problem.\n'
          '- Be reachable and ready when a provider is on the way.\n'
          '- Treat providers with courtesy and respect.\n'
          '- Agree the price and payment method directly with the provider '
          'before work begins, unless the app states otherwise.',
    ),
    (
      '4. Provider responsibilities',
      '- Offer only the services you are qualified, equipped and legally '
          'permitted to perform.\n'
          '- Keep your availability and live location accurate, and go '
          'offline when you cannot take requests.\n'
          '- Hold any licences, permits and insurance required by law.\n'
          '- Perform services with reasonable skill and care, and be '
          'honest about prices and arrival times.\n'
          '- You act as an independent provider, not as our employee or '
          'agent.',
    ),
    (
      '5. Requests, pricing and payment',
      'Prices, fees and payment methods are agreed between the driver and '
          'the provider. Unless the app clearly states otherwise, we do not '
          'collect or hold payments and are not responsible for payment '
          'disputes between users. You are responsible for any taxes that '
          'apply to you.',
    ),
    (
      '6. Acceptable use',
      'You agree not to:\n'
          '- submit false, misleading or prank requests;\n'
          '- harass, threaten, discriminate against or endanger others;\n'
          '- share another person\'s contact details outside the purpose of '
          'a request;\n'
          '- post fake ratings or reports;\n'
          '- tamper with, reverse engineer or interfere with the app;\n'
          '- use the app for anything unlawful.',
    ),
    (
      '7. Emergencies',
      'The app is not an emergency service. If anyone is injured or in '
          'danger, contact the local emergency services immediately (for '
          'example 119 for police or 1990 for an ambulance in Sri Lanka) '
          'before using the app.',
    ),
    (
      '8. Ratings, reports and moderation',
      'Users may rate each other and submit reports. We may review reports '
          'and, at our discretion, warn, restrict or remove accounts that '
          'breach these terms, receive repeated complaints or put others at '
          'risk.',
    ),
    (
      '9. Privacy',
      'Our Privacy Policy explains how we collect and use your '
          'information. By using the app you also agree to it.',
    ),
    (
      '10. Intellectual property',
      'The app, its design, logo and content belong to us or our licensors. '
          'You may use the app for its intended purpose but may not copy, '
          'modify or distribute any part of it without permission.',
    ),
    (
      '11. Disclaimers',
      'The app is provided "as is" and "as available". We do not guarantee '
          'that a provider will be available, arrive at a particular time or '
          'complete a job successfully, or that the app will be '
          'uninterrupted or error-free. We do not verify every provider or '
          'driver and do not endorse the quality or safety of any service '
          'offered through the app.',
    ),
    (
      '12. Limitation of liability',
      'To the fullest extent permitted by law, we are not liable for '
          'any loss, damage, injury or delay arising from services provided '
          'by providers, from disputes between users, or from your use of '
          'or inability to use the app. Nothing in these terms limits '
          'liability that cannot be limited by law.',
    ),
    (
      '13. Suspension and termination',
      'You may stop using the app and ask us to delete your account at any '
          'time. We may suspend or terminate access if you breach these '
          'terms or if required by law.',
    ),
    (
      '14. Governing law',
      'These terms are governed by the laws of Sri Lanka, and the courts of '
          'Sri Lanka have jurisdiction over any dispute, unless the law '
          'requires otherwise.',
    ),
    (
      '15. Changes to these terms',
      'We may update these terms from time to time. We will notify you of '
          'material changes in the app. Continued use after changes take '
          'effect means you accept them.',
    ),
    (
      '16. Contact us',
      'Questions about these terms? Email $_supportEmail or call '
          '$_supportPhone.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentPage(
      title: 'Terms & Conditions',
      intro: _intro,
      sections: _sections,
    );
  }
}

/// Shared layout for long-form legal text.
class _LegalDocumentPage extends StatelessWidget {
  final String title;
  final String intro;
  final List<(String, String)> sections;

  const _LegalDocumentPage({
    required this.title,
    required this.intro,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(
      fontSize: 14,
      height: 1.55,
      color: Colors.grey.shade800,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text(
              _legalUpdated,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            Text(intro, style: bodyStyle),
            const SizedBox(height: 24),
            for (final (heading, body) in sections) ...[
              Text(
                heading,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(body, style: bodyStyle),
              const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Report
// ============================================================

/// Saves a report to the `reports` collection in Firestore:
/// { uid, category, message, createdAt }.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  static const List<String> _categories = [
    'App problem',
    'Provider behaviour',
    'Driver behaviour',
    'Payment issue',
    'Safety concern',
    'Other',
  ];

  final _messageController = TextEditingController();
  String _category = _categories.first;
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_sending) return;
    final message = _messageController.text.trim();
    if (message.length < 10) {
      _snack('Please describe the problem in a bit more detail');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'uid': FirebaseAuth.instance.currentUser?.uid,
        'category': _category,
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report sent. Thank you!')));
    } catch (_) {
      _snack('Could not send your report. Try again.');
      if (mounted) setState(() => _sending = false);
    }
  }

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
          'Report',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    'What is this about?',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _categories)
                        ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          showCheckmark: false,
                          backgroundColor: Colors.white,
                          selectedColor: _brandRed.withValues(alpha: 0.12),
                          side: BorderSide(
                            color: _category == c
                                ? _brandRed
                                : Colors.grey.shade300,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            color: _category == c ? _brandRed : Colors.black87,
                          ),
                          onSelected: (_) => setState(() => _category = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Details',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    minLines: 5,
                    maxLines: 8,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Tell us what happened…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.black,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _sending ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit report',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
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
