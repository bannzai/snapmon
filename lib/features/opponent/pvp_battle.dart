import '../../domain/battle/battle_state.dart';
import '../dex/owned_monster.dart';

/// 人との対戦に出る 1 人。Firestore の `pvpBattles/{battleID}` の `host` / `guest`
/// (functions/src/pvp_battle_rules.ts の `PvpTrainer`) の形。
class PvpTrainer {
  /// 対戦に出る 1 人を作る。
  const PvpTrainer({
    required this.uid,
    required this.displayName,
    required this.iconPath,
    required this.monsters,
  });

  /// `pvpBattles/{battleID}` の `host` / `guest` [json] から読む。
  /// モンスターは他人に見せてよい項目だけで、元の写真の参照を持たない (`MonsterDefinition.sourcePhotoReference` は null)。
  factory PvpTrainer.fromJson({required Map<String, dynamic> json}) =>
      PvpTrainer(
        uid: json['uid'] as String,
        displayName: json['displayName'] as String,
        iconPath: json['iconPath'] as String?,
        monsters: [
          for (final monsterJson in json['monsters'] as List<dynamic>)
            OwnedMonster.fromJson(json: monsterJson as Map<String, dynamic>),
        ],
      );

  /// uid (通報・ブロックの宛先と、勝者の判定に使う)。
  final String uid;

  /// 表示名。
  final String displayName;

  /// アイコンの Storage のパス。登録していなければ null。
  final String? iconPath;

  /// 組み合わせた時点の手持ちの写し (手持ちの順。1〜3 体)。2 人の端末がこの写しから同じ計算をする。
  final List<OwnedMonster> monsters;
}

/// 人との対戦で、2 人の行動がそろって公開された 1 ターン (functions/src/pvp_battle_rules.ts の `PvpTurn`)。
typedef PvpTurn = ({
  /// 先に待っていた側 ([PvpBattle.host]) の行動。
  BattleAction hostAction,

  /// 後から来た側 ([PvpBattle.guest]) の行動。
  BattleAction guestAction,
});

/// 人との対戦の状態 (`pvpBattles/{battleID}` の `status`)。
enum PvpBattleStatus {
  /// 進行中。
  active,

  /// 勝者が決まって終わった。
  finished,

  /// 勝敗を付けずに終わった (どちらも行動を選ばなかった・ブロックした・2 人の端末の勝者が食い違った)。
  /// 保存している値は `void` (Dart の予約語のため、列挙の名前にできない)。
  noContest,
}

/// 人との対戦がどう終わったか (`pvpBattles/{battleID}` の `finishReason`)。
enum PvpFinishReason {
  /// 端末の計算の決着を利用者が報告した。
  result,

  /// 行動の期限を過ぎた。
  timeout,

  /// 2 人の報告した勝者が食い違った。
  mismatch,

  /// 片方が相手をブロックした。
  blocked,
}

/// 人との対戦 1 戦。Firestore の `pvpBattles/{battleID}` (functions/src/pvp_battle_rules.ts の `PvpBattleDocument`) のうち端末が使う項目。
class PvpBattle {
  /// 人との対戦 1 戦を作る。
  const PvpBattle({
    required this.battleID,
    required this.host,
    required this.guest,
    required this.randomSeed,
    required this.battleDate,
    required this.turns,
    required this.turnSeconds,
    required this.status,
    required this.winnerUID,
    required this.finishReason,
  });

  /// ID が [battleID] の `pvpBattles/{battleID}` のドキュメント [json] から読む。
  factory PvpBattle.fromJson({
    required String battleID,
    required Map<String, dynamic> json,
  }) => PvpBattle(
    battleID: battleID,
    host: PvpTrainer.fromJson(json: json['host'] as Map<String, dynamic>),
    guest: PvpTrainer.fromJson(json: json['guest'] as Map<String, dynamic>),
    randomSeed: json['randomSeed'] as int,
    battleDate: DateTime.parse(json['battleDate'] as String),
    turns: [
      for (final turnJson in json['turns'] as List<dynamic>)
        (
          hostAction: battleActionFromJson(
            json:
                (turnJson as Map<String, dynamic>)['hostAction']
                    as Map<String, dynamic>,
          ),
          guestAction: battleActionFromJson(
            json: turnJson['guestAction'] as Map<String, dynamic>,
          ),
        ),
    ],
    turnSeconds: json['turnSeconds'] as int,
    status: switch (json['status'] as String) {
      'active' => PvpBattleStatus.active,
      'finished' => PvpBattleStatus.finished,
      'void' => PvpBattleStatus.noContest,
      final status => throw FormatException('知らない対戦の状態 $status'),
    },
    winnerUID: json['winnerUID'] as String?,
    finishReason: switch (json['finishReason'] as String?) {
      null => null,
      final finishReason => PvpFinishReason.values.byName(finishReason),
    },
  );

  /// 対戦の ID。自分のバトルの記録 (`users/{uid}/battles/{battleID}`) の ID でもある。
  final String battleID;

  /// 先に待っていた側。2 人の端末は、この側をバトルの計算の利用者の陣営 (`BattleSideID.player`) として計算する。
  final PvpTrainer host;

  /// 後から来た側。
  final PvpTrainer guest;

  /// バトルの乱数の種。
  final int randomSeed;

  /// 対戦日 (日本時間の日付)。
  final DateTime battleDate;

  /// 行動がそろって公開されたターン (古い順)。
  final List<PvpTurn> turns;

  /// 1 ターンの行動を選ぶ時間 (秒)。
  final int turnSeconds;

  /// 対戦の状態。
  final PvpBattleStatus status;

  /// 勝者の uid。[PvpBattleStatus.finished] の時だけ入る。
  final String? winnerUID;

  /// どう終わったか。進行中は null。
  final PvpFinishReason? finishReason;
}

/// 公開されたターンの行動 [json] (functions/src/pvp_battle_rules.ts の `PvpAction`) をバトルの計算の行動として読む。
BattleAction battleActionFromJson({required Map<String, dynamic> json}) =>
    switch (json['kind'] as String) {
      'move' => UseMoveAction(moveID: json['moveID'] as String),
      'struggle' => const StruggleAction(),
      'switch' => SwitchMonsterAction(memberIndex: json['memberIndex'] as int),
      final kind => throw FormatException('知らない行動の種類 $kind'),
    };

/// バトルの計算の行動 [action] を、Functions の submitPvpAction に渡す形 (functions/src/pvp_battle_rules.ts の `PvpAction`) にする。
Map<String, Object> battleActionToJson({required BattleAction action}) =>
    switch (action) {
      UseMoveAction() => {'kind': 'move', 'moveID': action.moveID},
      StruggleAction() => {'kind': 'struggle'},
      SwitchMonsterAction() => {
        'kind': 'switch',
        'memberIndex': action.memberIndex,
      },
    };
