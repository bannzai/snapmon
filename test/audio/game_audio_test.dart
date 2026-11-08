import 'dart:async';

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
      waitsForUserInteractionBeforeBackgroundMusic: false,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.battle);
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.home.assetPath,
      BackgroundMusic.battle.assetPath,
    ]);
    // BGM は効果音 (1.0) より薄く流す (値の根拠は backgroundMusicVolume のコメント)
    expect(calls.playedBackgroundMusicVolumes, [0.2, 0.2]);
  });

  test('BGM を止めた後に同じ曲を求めると流し直す', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = fakeGameAudio(
      calls: calls,
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
      waitsForUserInteractionBeforeBackgroundMusic: false,
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
      waitsForUserInteractionBeforeBackgroundMusic: false,
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
    // オンに戻した時の再生も、通常の再生と同じ音量で流す
    expect(calls.playedBackgroundMusicVolumes, [0.2]);
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
      waitsForUserInteractionBeforeBackgroundMusic: false,
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
      waitsForUserInteractionBeforeBackgroundMusic: false,
    );
    await gameAudio.playSoundEffect(effect: SoundEffect.hit);
    await gameAudio.setSoundEffectsEnabled(enabled: false);
    await gameAudio.playSoundEffect(effect: SoundEffect.victory);
    expect(calls.playedSoundEffectAssetPaths, [SoundEffect.hit.assetPath]);
    expect(calls.savedSettings, [
      (key: AudioSettingKey.soundEffects, value: false),
    ]);
  });

  test('BGM の読み込み中にオフにしても、読み込みが終わってから止めて、最後の設定を保存する', () async {
    final playStarted = Completer<void>();
    final playCompleter = Completer<void>();
    var stopCount = 0;
    final savedValues = <bool>[];
    final gameAudio = GameAudio(
      playBackgroundMusicAsset: ({required assetPath, required volume}) {
        playStarted.complete();
        return playCompleter.future;
      },
      stopBackgroundMusicAsset: () async => stopCount += 1,
      playSoundEffectAsset: ({required assetPath}) async {},
      saveSetting: ({required key, required value}) async =>
          savedValues.add(value),
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
      waitsForUserInteractionBeforeBackgroundMusic: false,
    );
    // 再生の完了は待ち行列が後ろの操作より先に待つため、ここでは待たない
    unawaited(gameAudio.playBackgroundMusic(music: BackgroundMusic.home));
    await playStarted.future;
    // 読み込み中にオフ → オン → オフと切り替える。停止は読み込みが終わった後に 1 回だけ行い、
    // 途中のオンと最後のオフ (もう反映済みの値) は重ねて反映しない。保存は最後の値 (オフ) だけ。
    // 切り替えは読み込みの完了 (playCompleter.complete) より前に積む必要があるため、待つのは完了の後
    final toggling = Future.wait([
      gameAudio.setBackgroundMusicEnabled(enabled: false),
      gameAudio.setBackgroundMusicEnabled(enabled: true),
      gameAudio.setBackgroundMusicEnabled(enabled: false),
    ]);
    expect(stopCount, 0);
    playCompleter.complete();
    await toggling;
    expect(stopCount, 1);
    expect(savedValues, [false]);
    expect(gameAudio.isBackgroundMusicEnabled, isFalse);
  });

  test('Web では最初の操作まで BGM を流さず、操作の後に最後に求められた曲を流す。2 回目の操作では流し直さない', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = GameAudio(
      playBackgroundMusicAsset: ({required assetPath, required volume}) async =>
          calls.playedBackgroundMusicAssetPaths.add(assetPath),
      stopBackgroundMusicAsset: () async => calls.stopBackgroundMusicCount += 1,
      playSoundEffectAsset: ({required assetPath}) async {},
      saveSetting: ({required key, required value}) async {},
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
      waitsForUserInteractionBeforeBackgroundMusic: true,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.battle);
    expect(calls.playedBackgroundMusicAssetPaths, isEmpty);

    await gameAudio.notifyUserInteraction();
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.battle.assetPath,
    ]);
    await gameAudio.notifyUserInteraction();
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.battle.assetPath,
    ]);
    // 操作の後に求めた曲は待たずに流す
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.battle.assetPath,
      BackgroundMusic.home.assetPath,
    ]);
  });

  test('Web で最初の操作の前に BGM をオンにしても流さず、操作の後に流す', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = GameAudio(
      playBackgroundMusicAsset: ({required assetPath, required volume}) async =>
          calls.playedBackgroundMusicAssetPaths.add(assetPath),
      stopBackgroundMusicAsset: () async => calls.stopBackgroundMusicCount += 1,
      playSoundEffectAsset: ({required assetPath}) async {},
      saveSetting: ({required key, required value}) async =>
          calls.savedSettings.add((key: key, value: value)),
      isBackgroundMusicEnabled: false,
      isSoundEffectsEnabled: true,
      waitsForUserInteractionBeforeBackgroundMusic: true,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.setBackgroundMusicEnabled(enabled: true);
    expect(calls.playedBackgroundMusicAssetPaths, isEmpty);
    expect(calls.savedSettings, [
      (key: AudioSettingKey.backgroundMusic, value: true),
    ]);

    await gameAudio.notifyUserInteraction();
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.home.assetPath,
    ]);
  });

  test('操作を待たない (iOS・Android) 時は、操作の通知が無くても求められた BGM をすぐ流す', () async {
    final calls = RecordedAudioCalls();
    final gameAudio = fakeGameAudio(
      calls: calls,
      isBackgroundMusicEnabled: true,
      isSoundEffectsEnabled: true,
      waitsForUserInteractionBeforeBackgroundMusic: false,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.home.assetPath,
    ]);
    await gameAudio.notifyUserInteraction();
    expect(calls.playedBackgroundMusicAssetPaths, [
      BackgroundMusic.home.assetPath,
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
      waitsForUserInteractionBeforeBackgroundMusic: false,
    );
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    await gameAudio.playBackgroundMusic(music: BackgroundMusic.home);
    expect(playCount, 2);
    await gameAudio.playSoundEffect(effect: SoundEffect.hit);
    await gameAudio.stopBackgroundMusic();
  });
}
