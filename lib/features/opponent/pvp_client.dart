import 'dart:typed_data';

import '../../domain/master/master_data.dart';
import 'pvp_opponent.dart';
import 'report_reason.dart';

/// トレーナー (自分か対戦の相手) の見え方。自分の分は Functions の getDisplayName が返す形 (functions/src/pvp.ts) で、
/// CPU トレーナーは見本データの名前とアイコン無し (null) で作る。
typedef TrainerProfile = ({
  /// 表示名。
  String displayName,

  /// 検査を通したアイコンの Storage のパス (`users/{uid}/icons/`)。登録していない時は null で、既定の印を描く。
  String? iconPath,
});

/// 非同期 PvP の相手の取得・通報・ブロック・戦績・プロフィール (表示名とアイコン) を呼ぶ関数の組。
/// 対戦相手と設定の画面を Firebase と切り離してテストするため、実体 (lib/firebase/pvp.dart) は main.dart から渡す。
/// ログインが無い時 (DEBUG ビルドでログインを飛ばした時) に null を返す関数は、その旨を各関数に書く。
class PvpClient {
  /// 関数の組を作る。
  const PvpClient({
    required this.fetchOpponents,
    required this.fetchDefinitions,
    required this.reportMonster,
    required this.blockUser,
    required this.fetchBattleRecord,
    required this.fetchProfile,
    required this.updateDisplayName,
    required this.updateIcon,
  });

  /// 相手の候補 (最大 3 人。手持ちの平均レベルが自分に近い順) を返す。ログインが無い時は null。
  final Future<List<PvpOpponent>?> Function() fetchOpponents;

  /// [base] に、その場で作った定義 [definitionIds] (`definitions/{definitionId}`。相手のモンスターが参照する) を足して返す。
  final Future<MasterData> Function({
    required MasterData base,
    required List<String> definitionIds,
  })
  fetchDefinitions;

  /// [monsterOwnerUid] のモンスター [monsterId] を [reason] で通報する。
  final Future<void> Function({
    required String monsterOwnerUid,
    required String monsterId,
    required ReportReason reason,
  })
  reportMonster;

  /// [blockedUid] のユーザーをブロックする。
  final Future<void> Function({required String blockedUid}) blockUser;

  /// 記録した自分のバトルの勝ち数と負け数を返す。ログインが無い時は null。
  final Future<({int wins, int losses})?> Function() fetchBattleRecord;

  /// 自分の表示名とアイコンを返す。ログインが無い時は null。
  final Future<TrainerProfile?> Function() fetchProfile;

  /// 自分の表示名を [displayName] に変え、保存した名前を返す。使えない名前の時は Functions の理由を例外で投げる。
  final Future<String> Function({required String displayName})
  updateDisplayName;

  /// [photo] (生成に送る写真と同じ形の JPEG) を自分のアイコンにし、保存したアイコンの Storage のパスを返す。
  /// 人の顔が写る写真・不適切な写真の時は Functions の理由を例外で投げる。
  final Future<String> Function({required Uint8List photo}) updateIcon;
}
