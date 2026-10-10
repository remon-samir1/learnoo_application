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
          padding: const EdgeInsetsDirectional.only(start: 16.0),
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
            Text(
              'terms_privacy.intro'.tr(),
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 18,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _buildParagraph(
              'terms_privacy.p1'.tr(),
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              'terms_privacy.p2'.tr(),
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              'terms_privacy.p3'.tr(),
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              'terms_privacy.p4'.tr(),
            ),
            const SizedBox(height: 16),
            _buildParagraph(
              'terms_privacy.p5'.tr(),
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
