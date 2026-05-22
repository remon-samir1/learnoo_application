import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class TermsPrivacyScreen extends StatelessWidget {
  const TermsPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              shape: CircleBorder(side: BorderSide(color: Colors.grey[200]!)),
            ),
          ),
        ),
        title: Text(
          'terms_privacy.title'.tr(),
          style: const TextStyle(
            color: Color(0xFF2D3748),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How student data is collected, used, and protected inside the platform.',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 18,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _buildParagraph(
              '01 Learnoo may collect student information such as name, mobile number, email, university, faculty, selected centers, course activity, and support history to provide educational services effectively.',
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              '02 The platform may also use progress data, watch history, notes, exam records, and community interactions to personalize the learning experience.',
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              '03 Student data is used to manage access, deliver notifications, support communication, improve course recommendations, and maintain account security.',
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              '04 Sensitive account and activity data should be handled according to platform security standards, with access limited to authorized administrative roles when operationally necessary.',
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              '05 Learnoo does not display personal data publicly beyond the features required for learning interactions such as community, Q&A, or instructor communication, depending on the app settings.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 15,
        height: 1.6,
      ),
    );
  }
}
