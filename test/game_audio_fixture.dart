import 'package:snapmon/audio/game_audio.dart';

/// テスト用の [GameAudio] が受け取った呼び出し。
class RecordedAudioCalls {
  /// 流し始めた BGM のファイルのパス (呼ばれた順)。
  final List<String> playedBackgroundMusicAssetPaths = [];

  /// BGM を止めた回数。
  int stopBackgroundMusicCount = 0;

  /// 鳴らした効果音のファイルのパス (呼ばれた順)。
  final List<String> playedSoundEffectAssetPaths = [];

  /// 保存した設定 (呼ばれた順)。
  final List<({AudioSettingKey key, bool value})> savedSettings = [];
}

/// 音声のプラグインと端末の設定を呼ばずに [calls] へ呼び出しを残す [GameAudio] を返す。
/// [isBackgroundMusicEnabled]・[isSoundEffectsEnabled] は起動時に端末から読んだ設定の代わり。
GameAudio fakeGameAudio({
  required RecordedAudioCalls calls,
  required bool isBackgroundMusicEnabled,
  required bool isSoundEffectsEnabled,
}) => GameAudio(
  playBackgroundMusicAsset: ({required assetPath, required volume}) async {
    calls.playedBackgroundMusicAssetPaths.add(assetPath);
  },
  stopBackgroundMusicAsset: () async {
    calls.stopBackgroundMusicCount += 1;
  },
  playSoundEffectAsset: ({required assetPath}) async {
    calls.playedSoundEffectAssetPaths.add(assetPath);
  },
  saveSetting: ({required key, required value}) async {
    calls.savedSettings.add((key: key, value: value));
  },
  isBackgroundMusicEnabled: isBackgroundMusicEnabled,
  isSoundEffectsEnabled: isSoundEffectsEnabled,
  // Web の最初の操作を待つ振る舞いは test/audio/game_audio_test.dart が GameAudio を直接作って確かめる
  waitsForUserInteractionBeforeBackgroundMusic: false,
);
