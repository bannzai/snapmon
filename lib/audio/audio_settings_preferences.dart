import 'package:shared_preferences/shared_preferences.dart';

import 'game_audio.dart';

/// shared_preferences に保存する音の設定のキー。端末ごとの設定で、アカウントには紐づけない (Firestore の `settings/current` には置かない)。
const Map<AudioSettingKey, String> _preferenceKeys = {
  AudioSettingKey.backgroundMusic: 'audio.backgroundMusicEnabled',
  AudioSettingKey.soundEffects: 'audio.soundEffectsEnabled',
};

/// 端末に保存した [key] の設定を読む。保存していない (初回起動) 時は true (音は出す。設定画面で切れる)。
Future<bool> readAudioSettingFromPreferences({
  required AudioSettingKey key,
}) async =>
    (await SharedPreferences.getInstance()).getBool(_preferenceKeys[key]!) ??
    true;

/// [key] の設定 [value] を端末に保存する ([GameAudio.saveSetting] の実体)。
Future<void> saveAudioSettingToPreferences({
  required AudioSettingKey key,
  required bool value,
}) async {
  await (await SharedPreferences.getInstance()).setBool(
    _preferenceKeys[key]!,
    value,
  );
}
