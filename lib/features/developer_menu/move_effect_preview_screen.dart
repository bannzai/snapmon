import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/master/move_effect.dart';
import '../battle/battle_field_game.dart';
import '../battle/move_effect_sprite_sheets.dart';
import '../dex/owned_monster.dart';
import '../share/card_sharer.dart';

/// 技のエフェクトをバトルのフィールドで繰り返し再生する画面 (DEBUG ビルドの開発者メニューから開く)。
/// 全属性の技を当てるにはバトルを何度も重ねる必要があるため、スプライトシートの見え方をここでまとめて確かめる。
class MoveEffectPreviewScreen extends StatefulWidget {
  /// [playerMonster] と [opponentMonster] を場に出し、選んだエフェクトを [opponentMonster] に当て続ける画面を作る。
  const MoveEffectPreviewScreen({
    super.key,
    required this.playerMonster,
    required this.opponentMonster,
    required this.cardSharer,
  });

  /// 自分の場のモンスター。
  final OwnedMonster playerMonster;

  /// 相手の場のモンスター。エフェクトはこちらに当てる。
  final OwnedMonster opponentMonster;

  /// 切り出した被写体の画像の読み込みに使う。
  final CardSharer cardSharer;

  @override
  State<MoveEffectPreviewScreen> createState() =>
      _MoveEffectPreviewScreenState();
}

class _MoveEffectPreviewScreenState extends State<MoveEffectPreviewScreen> {
  // 被弾の 0.5 秒 (hitReactionSeconds) の再生が終わってから次を当て、スクリーンショットを撮る間も絵が出続けるようにする
  static const Duration _replayInterval = Duration(milliseconds: 600);

  late final BattleFieldGame _game = BattleFieldGame(
    playerMonster: widget.playerMonster,
    opponentMonster: widget.opponentMonster,
  );

  /// 読み込めた被写体の画像。画面を閉じる時に dispose する。
  final List<ui.Image> _loadedArtImages = [];

  /// 当て続けているエフェクトの id。null の間は何も当てない。
  String? _selectedEffectId;

  /// [_selectedEffectId] を当て続けるタイマー。
  Timer? _replayTimer;

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
        spriteSheetsByEffectId: moveEffectSpriteSheetsByEffectId,
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

  /// [effectId] のエフェクトを相手に当て続ける。前に選んでいたエフェクトは止める。
  void _replay({required String effectId}) {
    _replayTimer?.cancel();
    setState(() => _selectedEffectId = effectId);
    void hitOpponent() => _game.hit(
      defenderSide: BattleSideId.opponent,
      effect: MoveEffect(
        id: effectId,
        displayName: effectId,
        kind: 'particle',
        colorHex: '#FFFFFF',
      ),
    );
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
    appBar: AppBar(title: Text(_selectedEffectId ?? '技のエフェクトの見本')),
    body: Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: GameWidget(game: _game),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final MapEntry(key: effectId, value: spriteSheet)
                  in moveEffectSpriteSheetsByEffectId.entries)
                ListTile(
                  title: Text(effectId),
                  subtitle: Text(spriteSheet.assetName),
                  selected: effectId == _selectedEffectId,
                  onTap: () => _replay(effectId: effectId),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
