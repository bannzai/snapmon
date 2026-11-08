import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/master/master_data.dart';
import '../../domain/master/move_effect.dart';
import '../battle/battle_field_game.dart';
import '../battle/move_effect_sprite_sheets.dart';
import '../dex/owned_monster.dart';
import '../share/card_sharer.dart';

/// 技のエフェクトをバトルのフィールドで繰り返し再生する画面 (DEBUG ビルドの開発者メニューから開く)。
/// 全属性の技を当てるにはバトルを何度も重ねる必要があるため、スプライトシートの見え方をここでまとめて確かめる。
/// 一覧は [definitions] の effects のうちスプライトシートで描くもの (master の版 9 から技ごと。#224)。
class MoveEffectPreviewScreen extends StatefulWidget {
  /// [playerMonster] と [opponentMonster] を場に出し、選んだエフェクトを [opponentMonster] に当て続ける画面を作る。
  const MoveEffectPreviewScreen({
    super.key,
    required this.playerMonster,
    required this.opponentMonster,
    required this.cardSharer,
    required this.definitions,
  });

  /// 自分の場のモンスター。
  final OwnedMonster playerMonster;

  /// 相手の場のモンスター。エフェクトはこちらに当てる。
  final OwnedMonster opponentMonster;

  /// 切り出した被写体の画像の読み込みに使う。
  final CardSharer cardSharer;

  /// エフェクトの定義 (見本の master)。
  final MasterData definitions;

  @override
  State<MoveEffectPreviewScreen> createState() =>
      _MoveEffectPreviewScreenState();
}

/// [MoveEffectPreviewScreen] の状態。フィールドのゲームと、当て続けているエフェクトを持つ。
class _MoveEffectPreviewScreenState extends State<MoveEffectPreviewScreen> {
  /// 同じエフェクトを当て直す間隔。被弾の 0.5 秒 (hitReactionSeconds) の再生が終わってから次を当て、
  /// スクリーンショットを撮る間も絵が出続けるようにするため。
  static const Duration _replayInterval = Duration(milliseconds: 600);

  /// 見本の 2 体を場に出したバトルのフィールド。
  late final BattleFieldGame _game = BattleFieldGame(
    playerMonster: widget.playerMonster,
    opponentMonster: widget.opponentMonster,
  );

  /// 読み込めた被写体の画像。画面を閉じる時に dispose する。
  final List<ui.Image> _loadedArtImages = [];

  /// 当て続けているエフェクト。null の間は何も当てない。
  MoveEffect? _selectedEffect;

  /// [_selectedEffect] を当て続けるタイマー。
  Timer? _replayTimer;

  /// 一覧に出すエフェクト (スプライトシートで描くもの)。
  late final List<MoveEffect> _spriteSheetEffects = [
    for (final effect in widget.definitions.effects)
      if (effect.spriteSheet != null) effect,
  ];

  @override
  void initState() {
    super.initState();
    for (final artPath in {
      ?widget.playerMonster.artPath,
      ?widget.opponentMonster.artPath,
    }) {
      unawaited(_loadArtImage(artPath: artPath));
    }
    unawaited(
      loadMoveEffectSpriteSheets(
        game: _game,
        effects: _spriteSheetEffects,
        assetBundle: rootBundle,
      ),
    );
  }

  /// [artPath] の画像を読み、フィールドに渡す。読めなければログに残して絵の無いまま続ける。
  Future<void> _loadArtImage({required String artPath}) async {
    try {
      final artImage = await widget.cardSharer.loadArtImage(artPath: artPath);
      if (!mounted) {
        artImage.dispose();
        return;
      }
      _loadedArtImages.add(artImage);
      _game.applyArtImage(artPath: artPath, artImage: artImage);
    } catch (error) {
      debugPrint('$artPath: $error');
    }
  }

  /// [effect] を相手に当て続ける。前に選んでいたエフェクトは止める。
  void _replay({required MoveEffect effect}) {
    _replayTimer?.cancel();
    setState(() => _selectedEffect = effect);
    void hitOpponent() =>
        _game.hit(defenderSide: BattleSideId.opponent, effect: effect);
    hitOpponent();
    _replayTimer = Timer.periodic(_replayInterval, (_) => hitOpponent());
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    for (final artImage in _loadedArtImages) {
      artImage.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_selectedEffect?.displayName ?? '技のエフェクトの見本')),
    body: Column(
      children: [
        // 横長の画面でも一覧の高さが残るよう、フィールドと一覧で高さを分ける
        Expanded(child: GameWidget(game: _game)),
        Expanded(
          child: ListView.builder(
            itemCount: _spriteSheetEffects.length,
            itemBuilder: (context, index) {
              final effect = _spriteSheetEffects[index];
              return ListTile(
                key: Key('move-effect-preview-${effect.id}'),
                title: Text(effect.displayName),
                subtitle: Text('${effect.id} / ${effect.spriteSheet}'),
                selected: effect.id == _selectedEffect?.id,
                onTap: () => _replay(effect: effect),
              );
            },
          ),
        ),
      ],
    ),
  );
}
