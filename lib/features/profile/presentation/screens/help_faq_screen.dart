import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  int _expandedIndex = 0;

  List<Map<String, String>> get _faqs => [
    {
      'question': 'help_faq.q1'.tr(),
      'answer': 'help_faq.a1'.tr(),
    },
    {
      'question': 'help_faq.q2'.tr(),
      'answer': 'help_faq.a2'.tr(),
    },
    {
      'question': 'help_faq.q3'.tr(),
      'answer': 'help_faq.a3'.tr(),
    },
    {
      'question': 'help_faq.q4'.tr(),
      'answer': 'help_faq.a4'.tr(),
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faqsList = _faqs;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13151B) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF13151B) : Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              shape: CircleBorder(
                side: BorderSide(color: isDark ? const Color(0xFF383E52) : Colors.grey[200]!),
              ),
            ),
          ),
        ),
        title: Text(
          'help_faq.title'.tr(),
          style: TextStyle(
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF2D3748),
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
              style: TextStyle(color: isDark ? const Color(0xFFF8FAFC) : Colors.black87),
              decoration: InputDecoration(
                hintText: 'help_faq.search'.tr(),
                hintStyle: TextStyle(
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFFA0AEC0),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFFA0AEC0),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E212B) : Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF383E52) : Colors.grey[200]!,
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: Color(0xFF263EE2)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'help_faq.common_questions'.tr(),
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E212B) : Colors.white,
                border: Border.all(
                  color: isDark ? const Color(0xFF2E3344) : Colors.grey[200]!,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: List.generate(faqsList.length, (index) {
                  final isExpanded = _expandedIndex == index;
                  final isLast = index == faqsList.length - 1;
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
                                      faqsList[index]['question']!,
                                      style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFFF8FAFC)
                                            : const Color(0xFF334155),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_down
                                        : Icons.chevron_right,
                                    color: isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const SizedBox(height: 12),
                                Text(
                                  faqsList[index]['answer']!,
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF64748B),
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
                        Divider(
                          height: 1,
                          color: isDark ? const Color(0xFF2E3344) : Colors.grey[200],
                          thickness: 1,
                        ),
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
                icon: Icon(
                  Icons.email_outlined,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                ),
                label: Text(
                  'help_faq.contact_support'.tr(),
                  style: TextStyle(
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark ? const Color(0xFF383E52) : Colors.grey[300]!,
                  ),
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
