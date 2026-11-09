import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/features/battle/battle_screen.dart';

void main() {
  test('ログを読ませる間は 1 行 1.5 秒で、行の数に比例して延びる', () {
    expect(
      battleLogReadingDuration(logText: 'マグモン は たおれた'),
      const Duration(milliseconds: 1500),
    );
    expect(
      battleLogReadingDuration(logText: 'マグモン の ひのこ\nこうかは ばつぐんだ'),
      const Duration(milliseconds: 3000),
    );
  });
}
