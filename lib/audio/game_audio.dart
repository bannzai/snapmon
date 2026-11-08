import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 繰り返し流す BGM。素材の出どころとライセンスは assets/CREDITS.md。
enum BackgroundMusic {
  /// タイトルと下タブの画面 (図鑑・撮る・対戦) で流す落ち着いた曲。
  home('assets/audio/song18_0.mp3'),

  /// バトル画面で流す曲。
  battle('assets/audio/battleThemeA.mp3');

  const BackgroundMusic(this.assetPath);

  /// pubspec.yaml の assets に書いたファイルのパス。
  final String assetPath;
}

/// 1 回だけ鳴らす効果音。素材の出どころとライセンスは assets/CREDITS.md。
enum SoundEffect {
  /// 技が当たった時。
  hit('assets/audio/sfx_sounds_damage1.wav'),

  /// モンスターが倒れた時。
  faint('assets/audio/sfx_sounds_negative2.wav'),

  /// バトルに勝った時。
  victory('assets/audio/sfx_sounds_fanfare1.wav'),

  /// バトルに負けた時。
  defeat('assets/audio/sfx_sounds_negative1.wav');

  const SoundEffect(this.assetPath);

  /// pubspec.yaml の assets に書いたファイルのパス。
  final String assetPath;
}

/// BGM の音量。効果音とログの文言を BGM より目立たせるため、効果音 (1.0) より下げた。
const double backgroundMusicVolume = 0.5;

/// BGM・効果音の再生と、設定画面の「BGM」「効果音」のオン・オフ。
/// 画面を音声のプラグイン (flame_audio) と端末の設定の保存 (shared_preferences) から切り離してテストするため、実体は main.dart から渡す
/// (lib/audio/flame_game_audio.dart・audio_settings_preferences.dart)。
/// オン・オフを変えた時に通知し、設定画面のスイッチが追従する。
class GameAudio extends ChangeNotifier {
  /// [isBackgroundMusicEnabled]・[isSoundEffectsEnabled] は起動時に端末から読んだ設定の値。
  GameAudio({
    required this.playBackgroundMusicAsset,
    required this.stopBackgroundMusicAsset,
    required this.playSoundEffectAsset,
    required this.saveSetting,
    required bool isBackgroundMusicEnabled,
    required bool isSoundEffectsEnabled,
  }) : _isBackgroundMusicEnabled = isBackgroundMusicEnabled,
       _isSoundEffectsEnabled = isSoundEffectsEnabled;

  /// [assetPath] の BGM を [volume] で繰り返し流す。流れている BGM があれば差し替える。
  final Future<void> Function({
    required String assetPath,
    required double volume,
  })
  playBackgroundMusicAsset;

  /// 流れている BGM を止める。流れていなくても失敗しない。
  final Future<void> Function() stopBackgroundMusicAsset;

  /// [assetPath] の効果音を 1 回鳴らす。
  final Future<void> Function({required String assetPath}) playSoundEffectAsset;

  /// 設定 ([AudioSettingKey]) のオン・オフを端末に保存する。
  final Future<void> Function({
    required AudioSettingKey key,
    required bool value,
  })
  saveSetting;

  bool _isBackgroundMusicEnabled;
  bool _isSoundEffectsEnabled;

  /// 最後に求められた BGM。止めた後と、まだ求められていない間は null。
  /// オフからオンに戻した時に、この曲を流し直す。
  BackgroundMusic? _requestedBackgroundMusic;

  /// 実際に流れている BGM。再生に失敗した時 (Web でユーザーの操作の前に流そうとした時) は null に戻し、次に求められた時に流し直す。
  BackgroundMusic? _playingBackgroundMusic;

  /// BGM を流すか (設定画面の「BGM」)。
  bool get isBackgroundMusicEnabled => _isBackgroundMusicEnabled;

  /// 効果音を鳴らすか (設定画面の「効果音」)。
  bool get isSoundEffectsEnabled => _isSoundEffectsEnabled;

  /// [music] を流す。同じ曲が流れている時は流し直さない (画面を行き来するたびに曲が頭に戻らないため)。
  /// オフの間は流さず、オンに戻した時に流す曲として覚える。
  Future<void> playBackgroundMusic({required BackgroundMusic music}) async {
    _requestedBackgroundMusic = music;
    if (!_isBackgroundMusicEnabled || _playingBackgroundMusic == music) {
      return;
    }
    _playingBackgroundMusic = music;
    try {
      await playBackgroundMusicAsset(
        assetPath: music.assetPath,
        volume: backgroundMusicVolume,
      );
    } catch (error) {
      // 音が出なくてもゲームは止めない。流れていない曲を流れていることにしないため、次に求められた時に流し直す
      debugPrint('${music.assetPath}: $error');
      if (_playingBackgroundMusic == music) {
        _playingBackgroundMusic = null;
      }
    }
  }

  /// 流れている BGM を止める。次に [playBackgroundMusic] が呼ばれるまで何も流れない。
  Future<void> stopBackgroundMusic() async {
    _requestedBackgroundMusic = null;
    _playingBackgroundMusic = null;
    try {
      await stopBackgroundMusicAsset();
    } catch (error) {
      debugPrint(error.toString());
    }
  }

  /// [effect] を 1 回鳴らす。オフの間は鳴らさない。
  Future<void> playSoundEffect({required SoundEffect effect}) async {
    if (!_isSoundEffectsEnabled) {
      return;
    }
    try {
      await playSoundEffectAsset(assetPath: effect.assetPath);
    } catch (error) {
      debugPrint('${effect.assetPath}: $error');
    }
  }

  /// 「BGM」のオン・オフを変えて保存する。オフにすると流れている BGM を止め、オンにすると最後に求められた曲を流す。
  Future<void> setBackgroundMusicEnabled({required bool enabled}) async {
    if (_isBackgroundMusicEnabled == enabled) {
      return;
    }
    _isBackgroundMusicEnabled = enabled;
    notifyListeners();
    final requested = _requestedBackgroundMusic;
    if (enabled) {
      if (requested != null) {
        await playBackgroundMusic(music: requested);
      }
    } else {
      _playingBackgroundMusic = null;
      try {
        await stopBackgroundMusicAsset();
      } catch (error) {
        debugPrint(error.toString());
      }
    }
    await saveSetting(key: AudioSettingKey.backgroundMusic, value: enabled);
  }

  /// 「効果音」のオン・オフを変えて保存する。
  Future<void> setSoundEffectsEnabled({required bool enabled}) async {
    if (_isSoundEffectsEnabled == enabled) {
      return;
    }
    _isSoundEffectsEnabled = enabled;
    notifyListeners();
    await saveSetting(key: AudioSettingKey.soundEffects, value: enabled);
  }
}

/// 端末に保存する音の設定の名前。保存の実体 (shared_preferences のキー) は lib/audio/audio_settings_preferences.dart。
enum AudioSettingKey {
  /// BGM を流すか。
  backgroundMusic,

  /// 効果音を鳴らすか。
  soundEffects,
}

/// 子の木の画面が BGM・効果音を鳴らすのに使う [GameAudio]。アプリのルート ([SnapmonApp]) が 1 つ置き、
/// 画面は [GameAudioScope.of] で引く (バトル画面・設定画面まで引数で渡す段が深いため。StorageImageLoaderScope と同じ形)。
class GameAudioScope extends InheritedNotifier<GameAudio> {
  /// [gameAudio] を使う範囲を作る。
  const GameAudioScope({
    super.key,
    required GameAudio gameAudio,
    required super.child,
  }) : super(notifier: gameAudio);

  /// [context] から見える [GameAudio]。オン・オフの変更を build で追うため、依存として登録する (スイッチの表示が追従する)。
  /// 無い時は throw する (テストは GameAudioScope で包んで渡す)。
  static GameAudio of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameAudioScope>()!.notifier!;

  /// [context] から見える [GameAudio] を、依存として登録せずに引く。initState・dispose のように build の外で鳴らす時に使う。
  static GameAudio read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GameAudioScope>()!.notifier!;
}
