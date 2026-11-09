import 'package:flutter/material.dart';

/// 属性ごとのアイコン。技のカードの名前の右端に、属性の色の丸に白で描く (https://github.com/bannzai/snapmon/issues/281 。
/// bannzai の「属性ごとのアイコンを決めよう」)。対象は [SnapmonColors.elementTypes] と同じ master の版 8 の 23 属性で、
/// それぞれの名前から連想できる Material Icons を選んだ (選定は agent)。master に無い属性 (その場で作った定義) は
/// [elementTypeFallbackIcon] で描く。
const Map<String, IconData> elementTypeIcons = {
  'fire': Icons.local_fire_department,
  'water': Icons.water_drop,
  'grass': Icons.grass,
  'thunder': Icons.bolt,
  'earth': Icons.terrain,
  'steel': Icons.shield,
  'wood': Icons.park,
  'light': Icons.wb_sunny,
  'dark': Icons.dark_mode,
  'poison': Icons.science,
  'sound': Icons.music_note,
  'beast': Icons.pets,
  'bug': Icons.bug_report,
  'bird': Icons.flutter_dash,
  'fish': Icons.set_meal,
  'ice': Icons.ac_unit,
  'wind': Icons.air,
  'flower': Icons.local_florist,
  'machine': Icons.smart_toy,
  'sweets': Icons.cake,
  'ghost': Icons.blur_on,
  'dragon': Icons.flare,
  'paper': Icons.description,
};

/// [elementTypeIcons] に無い属性のアイコン。生成でその場に作られた属性は名前が決まっていないため、「新しく生まれた」を表す星にした。
const IconData elementTypeFallbackIcon = Icons.auto_awesome;

/// [elementTypeId] の属性のアイコンを返す。
IconData elementTypeIcon({required String elementTypeId}) =>
    elementTypeIcons[elementTypeId] ?? elementTypeFallbackIcon;
