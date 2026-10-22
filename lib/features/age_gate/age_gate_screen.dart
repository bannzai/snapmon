import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import 'age_confirmation.dart';

/// 初回起動の最初の画面。生年月を入力してもらう。
/// 入力の前に使える年齢を示さず、年齢の既定値も置かない (FTC の COPPA の FAQ D.7 "ask age information in a
/// neutral manner"・"does not default to an age 13 or over"。
/// https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions )。
class AgeGateScreen extends StatefulWidget {
  /// 年齢の確認の画面を作る。
  const AgeGateScreen({super.key, required this.ageConfirmationStore});

  /// 入力した生年月の保存先。
  final AgeConfirmationStore ageConfirmationStore;

  @override
  State<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends State<AgeGateScreen> {
  final TextEditingController _birthYearController = TextEditingController();
  final TextEditingController _birthMonthController = TextEditingController();
  bool _showsInvalidInput = false;

  /// 入力できる最も古い生まれ年を今年から何年前までにするか。実在しうる年齢の上限を少し超える幅にした。
  static const int _oldestBirthYearOffset = 120;

  @override
  void dispose() {
    _birthYearController.dispose();
    _birthMonthController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final today = widget.ageConfirmationStore.today();
    final birthYear = int.tryParse(_birthYearController.text);
    final birthMonth = int.tryParse(_birthMonthController.text);
    if (birthYear == null ||
        birthMonth == null ||
        birthMonth < 1 ||
        birthMonth > 12 ||
        birthYear < today.year - _oldestBirthYearOffset ||
        birthYear * 12 + birthMonth > today.year * 12 + today.month) {
      setState(() => _showsInvalidInput = true);
      return;
    }
    await widget.ageConfirmationStore.answer(
      birthYear: birthYear,
      birthMonth: birthMonth,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 40),
        children: [
          const Text('snapmon', style: SnapmonTextStyles.logo),
          const SizedBox(height: 32),
          const Text('生まれた年と月を\n入力してください', style: SnapmonTextStyles.hero),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _NumberField(
                  key: const Key('birthYearField'),
                  controller: _birthYearController,
                  label: '年',
                  hint: '西暦',
                  maximumLength: 4,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _NumberField(
                  key: const Key('birthMonthField'),
                  controller: _birthMonthController,
                  label: '月',
                  hint: '1〜12',
                  maximumLength: 2,
                ),
              ),
            ],
          ),
          if (_showsInvalidInput) ...[
            const SizedBox(height: 12),
            Text(
              '正しい年と月を入力してください',
              style: SnapmonTextStyles.caption.copyWith(
                color: SnapmonColors.hitPointsLoss,
              ),
            ),
          ],
          const SizedBox(height: 32),
          FilledButton(onPressed: _submit, child: const Text('つぎへ')),
        ],
      ),
    ),
  );
}

/// 数字だけを受け付ける入力欄。
class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.maximumLength,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maximumLength;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maximumLength),
    ],
    style: SnapmonTextStyles.statValue.copyWith(
      color: SnapmonColors.textOnBackground,
    ),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: SnapmonTextStyles.caption,
      hintStyle: SnapmonTextStyles.caption,
      filled: true,
      fillColor: SnapmonColors.surface,
      border: const OutlineInputBorder(
        borderRadius: SnapmonRadii.button,
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// 年齢の確認で使えないと分かった人に出す画面。入力をやり直す導線は置かない。
class AgeRestrictedScreen extends StatelessWidget {
  /// 使えないことを伝える画面を作る。
  const AgeRestrictedScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 56, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('snapmon', style: SnapmonTextStyles.logo),
            SizedBox(height: 32),
            Text('ごめんなさい\nsnapmon は使えません', style: SnapmonTextStyles.hero),
            SizedBox(height: 16),
            Text(
              'snapmon は $minimumAge 歳以上の方が使えるゲームです',
              style: SnapmonTextStyles.body,
            ),
          ],
        ),
      ),
    ),
  );
}
