import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  int _expandedIndex = 0;

  final List<Map<String, String>> _faqs = [
    {
      'question': 'How do I join a live session?',
      'answer': 'Lorem ipsum dolor sit amet consectetur. Proin fermentum morbi gravida magna molestie lacinia id purus felis.',
    },
    {
      'question': 'Where can I find my course notes?',
      'answer': 'You can find your course notes in the materials section of your respective course dashboard.',
    },
    {
      'question': 'How to reset my password?',
      'answer': 'Go to the login screen and tap on "Forgot Password" to receive a reset link on your registered email.',
    },
    {
      'question': 'Troubleshooting video playback',
      'answer': 'Check your internet connection or try clearing the app cache if you experience video playback issues.',
    },
  ];

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
          'help_faq.title'.tr(),
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
            TextField(
              decoration: InputDecoration(
                hintText: 'help_faq.search'.tr(),
                hintStyle: const TextStyle(color: Color(0xFFA0AEC0)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF263EE2)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'help_faq.common_questions'.tr(),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: List.generate(_faqs.length, (index) {
                  final isExpanded = _expandedIndex == index;
                  final isLast = index == _faqs.length - 1;
                  return Column(
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedIndex = isExpanded ? -1 : index;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _faqs[index]['question']!,
                                      style: const TextStyle(
                                        color: Color(0xFF334155),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _faqs[index]['answer']!,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    height: 1.5,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (!isLast)
                        Divider(height: 1, color: Colors.grey[200], thickness: 1),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.email_outlined, color: Color(0xFF475569)),
                label: Text(
                  'help_faq.contact_support'.tr(),
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
