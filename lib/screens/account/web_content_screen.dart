import 'package:flutter/material.dart';

/// Displays Privacy Policy or Terms of Service content
/// In production, this would load from a URL using webview_flutter package
class WebContentScreen extends StatelessWidget {
  final String title;
  final String contentType; // 'privacy' or 'terms'

  const WebContentScreen({
    super.key,
    required this.title,
    required this.contentType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last Updated: January 2026',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            if (contentType == 'privacy') ..._buildPrivacyContent(),
            if (contentType == 'terms') ..._buildTermsContent(),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Questions?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Contact us at support@bestcut.pk for any questions about our ${contentType == 'privacy' ? 'privacy practices' : 'terms of service'}.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPrivacyContent() {
    return [
      _buildSection(
        'Information We Collect',
        'When you use Best Cut, we collect information you provide directly to us, such as:\n\n'
        '• Account information (name, email, phone number)\n'
        '• Profile information\n'
        '• Booking and transaction history\n'
        '• Location data (with your permission)\n'
        '• Device and usage information',
      ),
      _buildSection(
        'How We Use Your Information',
        'We use the information we collect to:\n\n'
        '• Provide, maintain, and improve our services\n'
        '• Process transactions and send related information\n'
        '• Send you technical notices and support messages\n'
        '• Respond to your comments and questions\n'
        '• Monitor and analyze trends, usage, and activities',
      ),
      _buildSection(
        'Information Sharing',
        'We may share your information in the following situations:\n\n'
        '• With barbers you book with (limited contact info)\n'
        '• With service providers who assist our operations\n'
        '• To comply with legal obligations\n'
        '• To protect the rights and safety of our users',
      ),
      _buildSection(
        'Data Security',
        'We implement appropriate security measures to protect your personal information. However, no method of transmission over the Internet is 100% secure.',
      ),
      _buildSection(
        'Your Rights',
        'You have the right to:\n\n'
        '• Access your personal data\n'
        '• Correct inaccurate data\n'
        '• Request deletion of your data\n'
        '• Opt-out of marketing communications',
      ),
    ];
  }

  List<Widget> _buildTermsContent() {
    return [
      _buildSection(
        'Acceptance of Terms',
        'By accessing or using the Best Cut app, you agree to be bound by these Terms of Service and all applicable laws and regulations.',
      ),
      _buildSection(
        'Use of Services',
        'You agree to use our services only for lawful purposes and in accordance with these Terms. You must not:\n\n'
        '• Use the service for any illegal purpose\n'
        '• Attempt to gain unauthorized access\n'
        '• Interfere with or disrupt the service\n'
        '• Impersonate any person or entity',
      ),
      _buildSection(
        'Booking & Cancellation',
        '• Bookings are subject to availability\n'
        '• Cancellation policies may vary by barber\n'
        '• A 50% cancellation fee may apply for customer cancellations\n'
        '• Full refunds are provided for barber cancellations',
      ),
      _buildSection(
        'Payments',
        '• All payments are processed securely\n'
        '• Wallet balances are non-refundable\n'
        '• Prices are in Pakistani Rupees (PKR)\n'
        '• We reserve the right to modify pricing',
      ),
      _buildSection(
        'Liability Limitations',
        'Best Cut acts as a platform connecting customers with barbers. We are not responsible for:\n\n'
        '• Quality of services provided by barbers\n'
        '• Disputes between customers and barbers\n'
        '• Any damages arising from use of the platform',
      ),
      _buildSection(
        'Account Termination',
        'We reserve the right to terminate or suspend your account at any time for violations of these terms or any other reason at our discretion.',
      ),
    ];
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
