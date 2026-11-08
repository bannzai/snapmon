import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/audio/game_audio.dart';

import '../game_audio_fixture.dart';

void main() {
  test('同じ BGM を続けて求めても流し直さず、別の曲を求めると差し替える', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = fakeGameAudio(
      calls: calls,
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.battle);
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.home.assetPath,
      BackgroundMusic.battle.assetPath,
    ]);
  });

  test('BGM を止めた後に同じ曲を求めると流し直す', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = fakeGameAudio(
      calls: calls,
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.battle);
    await gameAudio.stopBackgroundMusic();
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.battle);
    expect(calls.stopBackgroundMusicCount, 1);
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.battle.assetPath,
      BackgroundMusic.battle.assetPath,
    ]);
  });

  test('BGM がオフの間は流さず、オンにすると最後に求められた曲を流して設定を保存する', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = fakeGameAudio(
      calls: calls,
      isBackgroundMusicEnabled: false,
      isSoundEffectsEnabled: true,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.battle);
    expect(calls.playedBackgroundMusicAssetPaths, isEmpty);

    var notifiedCount = 0;
    gameAudio.addListener(() => notifiedCount += 1);
    await gameAudio.setBackgroundMusicEnabled(enabled: true);
    expect(gameAudio.isBackgroundMusicEnabled, isTrue);
    expect(notifiedCount, 1);
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.battle.assetPath,
    ]);
    expect(calls.savedSettings, [
      (key: AudioSettingKey.backgroundMusic, value: true),
    ]);
  });

  test('BGM をオフにすると流れている曲を止め、同じ値に変えても何もしない', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = fakeGameAudio(
      calls: calls,
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.setBackgroundMusicEnabled(enabled: false);
    expect(calls.stopBackgroundMusicCount, 1);
    expect(calls.savedSettings, [
      (key: AudioSettingKey.backgroundMusic, value: false),
    ]);

    await gameAudio.setBackgroundMusicEnabled(enabled: false);
    expect(calls.stopBackgroundMusicCount, 1);
    expect(calls.savedSettings.length, 1);
  });

  test('効果音はオンの時だけ鳴り、オフに変えると設定を保存する', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = fakeGameAudio(
      calls: calls,
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
    );
    await gameAudio.playSoundEffect(effect: SoundEffect.hit);
    await gameAudio.setSoundEffectsEnabled(enabled: false);
    await gameAudio.playSoundEffect(effect: SoundEffect.victory);
    expect(calls.playedSoundEffectAssetPaths, [SoundEffect.hit.assetPath]);
    expect(calls.savedSettings, [
      (key: AudioSettingKey.soundEffects, value: false),
    ]);
  });

  test('再生に失敗しても throw せず、次に同じ曲を求めた時に流し直す', () async {
    var playCount = 0;
    final gameAudio = GameAudio(
      playBackgroundMusicAsset: ({required assetPath, required volume}) async {
        playCount += 1;
        if (playCount == 1) {
          throw StateError('NotAllowedError');
        }
      },
      stopBackgroundMusicAsset: () async => throw StateError('stop failed'),
      playSoundEffectAsset: ({required assetPath}) async =>
          throw StateError('play failed'),
      saveSetting: ({required key, required value}) async {},
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    expect(playCount, 2);
    await gameAudio.playSoundEffect(effect: SoundEffect.hit);
    await gameAudio.stopBackgroundMusic();
  });
}
