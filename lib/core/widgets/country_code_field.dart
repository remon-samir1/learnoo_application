import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;

import '../theme/app_colors.dart';

/// One country dialling code.
class CountryCode {
  const CountryCode(this.code, this.flag, this.nameKey);

  /// Dialling prefix without `+`, e.g. `20`.
  final String code;
  final String flag;
  final String nameKey;
}

/// Dialling codes offered on the web's `CountryCodeSelect`.
const List<CountryCode> kCountryCodes = [
  CountryCode('20', '🇪🇬', 'auth.country_egypt'),
  CountryCode('966', '🇸🇦', 'auth.country_ksa'),
  CountryCode('971', '🇦🇪', 'auth.country_uae'),
  CountryCode('965', '🇰🇼', 'auth.country_kuwait'),
  CountryCode('974', '🇶🇦', 'auth.country_qatar'),
  CountryCode('962', '🇯🇴', 'auth.country_jordan'),
];

const String kDefaultCountryCode = '20';

/// Phone input with a leading country-code picker.
///
/// Matches the web login form: the student types a national number and the
/// dialling code is prepended before the request goes out.
class CountryCodeField extends StatelessWidget {
  const CountryCodeField({
    super.key,
    required this.controller,
    required this.countryCode,
    required this.onCountryChanged,
    required this.label,
    required this.hintText,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String countryCode;
  final ValueChanged<String> onCountryChanged;
  final String label;
  final String hintText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = kCountryCodes.firstWhere(
      (c) => c.code == countryCode,
      orElse: () => kCountryCodes.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.labelGray,
          ),
        ),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.inputBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selected.code,
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    onChanged: enabled
                        ? (value) {
                            if (value != null) onCountryChanged(value);
                          }
                        : null,
                    items: kCountryCodes
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.code,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(c.flag, style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 6),
                                Text(
                                  '+${c.code}',
                                  style: const TextStyle(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(15),
                  ],
                  style: const TextStyle(color: AppColors.textDark),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(color: AppColors.inputHint),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.primaryBlue, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Full international number for the API: dialling code + national digits,
  /// with spaces and leading zeros stripped.
  static String fullNumber(String countryCode, String raw) {
    final national =
        raw.trim().replaceAll(RegExp(r'\s+'), '').replaceFirst(RegExp(r'^0+'), '');
    return '$countryCode$national';
  }

  /// Localised country name for [code].
  static String nameFor(String code) {
    final match = kCountryCodes.firstWhere(
      (c) => c.code == code,
      orElse: () => kCountryCodes.first,
    );
    return match.nameKey.tr();
  }
}
