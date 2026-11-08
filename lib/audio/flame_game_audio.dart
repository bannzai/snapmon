import 'package:flame_audio/flame_audio.dart';

import 'game_audio.dart';

/// flame_audio の BGM の再生を用意する (アプリが裏に回った時の一時停止と復帰の登録)。起動時に 1 回呼ぶ。2 回呼んでも登録は 1 回。
/// flame_audio は渡されたパスの前に既定で `assets/audio/` を足すため、接頭辞を空にして pubspec.yaml に書いたパス
/// ([BackgroundMusic.assetPath]・[SoundEffect.assetPath]) をそのまま渡せるようにする。
Future<void> initializeFlameAudio() {
  FlameAudio.updatePrefix('');
  return FlameAudio.bgm.initialize();
}

/// [assetPath] の BGM を [volume] で繰り返し流す ([GameAudio.playBackgroundMusicAsset] の実体)。
Future<void> playBackgroundMusicWithFlameAudio({
  required String assetPath,
  required double volume,
}) => FlameAudio.bgm.play(assetPath, volume: volume);

/// 流れている BGM を止める ([GameAudio.stopBackgroundMusicAsset] の実体)。
Future<void> stopBackgroundMusicWithFlameAudio() => FlameAudio.bgm.stop();

/// [assetPath] の効果音を 1 回鳴らす ([GameAudio.playSoundEffectAsset] の実体)。
Future<void> playSoundEffectWithFlameAudio({required String assetPath}) =>
    FlameAudio.play(assetPath);
