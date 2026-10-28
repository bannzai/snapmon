import 'dart:typed_data';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/owned_monster.dart';

/// テスト用の [MonsterGenerator] が受け取った呼び出し。
class RecordedGenerationCalls {
  /// uploadPhoto に渡された要求 ID (呼ばれた順)。
  final List<String> uploadedRequestIds = [];

  /// uploadMask に渡された要求 ID とマスク (呼ばれた順)。
  final List<({String requestId, Uint8List mask})> uploadedMasks = [];

  /// requestGeneration に渡された要求 ID (呼ばれた順)。
  final List<String> requestedRequestIds = [];

  /// requestGeneration に渡されたマスクの出どころ (呼ばれた順)。
  final List<GenerationMaskSource> requestedMaskSources = [];

  /// createSquareMask に渡された枠 (呼ばれた順)。
  final List<SquareCrop> squareMaskCrops = [];

  /// fetchGeneration に渡された要求 ID (呼ばれた順)。
  final List<String> fetchedRequestIds = [];

  /// logEvent に渡されたイベントとパラメータ (呼ばれた順)。
  final List<({AnalyticsEvent event, Map<String, Object>? parameters})>
  loggedEvents = [];
}

/// テストの写真の中身 (preparePhoto はそのまま返すため、画像として読める必要はない)。
final Uint8List testPhotoBytes = Uint8List.fromList([1, 2, 3]);

/// テストの OS の切り出しのマスクの中身 (createCutoutPreview は写真をそのまま返すため、画像として読める必要はない)。
final Uint8List testSubjectMaskBytes = Uint8List.fromList([4, 5, 6]);

/// テストの crop のマスクの中身。
final Uint8List testSquareMaskBytes = Uint8List.fromList([7, 8, 9]);

/// Firebase と端末の機能を呼ばずに [calls] へ呼び出しを残す [MonsterGenerator] を返す。
/// アルバムは [albumPhoto] を返し、要求 ID は `request-1`・`request-2`… の順に作る。
/// OS の切り出しは [createSubjectMask] の結果を返す (省くと、被写体を見つけて [testSubjectMaskBytes] を返す)。
/// crop のマスクは [createSquareMask] の結果 (省くと [testSquareMaskBytes])、プレビューは写真をそのまま返す。
/// uploadPhoto は [uploadError] があればそれを投げる (ログインしていない時の lib/firebase/monster_generation.dart と同じ)。
/// requestGeneration・fetchGeneration は [requestGeneration]・[fetchGeneration] の結果を返す。
MonsterGenerator fakeMonsterGenerator({
  required RecordedGenerationCalls calls,
  required Uint8List? albumPhoto,
  required Object? uploadError,
  required Future<GenerationResult> Function({required String requestId})
  requestGeneration,
  required Future<GenerationResult> Function({required String requestId})
  fetchGeneration,
  Future<Uint8List?> Function({required Uint8List photo})? createSubjectMask,
  Future<Uint8List> Function({
    required Uint8List photo,
    required SquareCrop crop,
  })?
  createSquareMask,
}) {
  var requestIdCount = 0;
  return MonsterGenerator(
    // テストの環境にはカメラが無い (Simulator と同じ)
    listCameras: () async => const [],
    pickAlbumPhoto: () async => albumPhoto,
    preparePhoto: ({required sourceBytes}) async => sourceBytes,
    createSubjectMask:
        createSubjectMask ?? ({required photo}) async => testSubjectMaskBytes,
    createSquareMask: ({required photo, required crop}) async {
      calls.squareMaskCrops.add(crop);
      return createSquareMask == null
          ? testSquareMaskBytes
          : createSquareMask(photo: photo, crop: crop);
    },
    createCutoutPreview: ({required photo, required mask}) async => photo,
    createRequestId: () => 'request-${++requestIdCount}',
    uploadPhoto: ({required requestId, required photo}) async {
      if (uploadError != null) {
        throw uploadError;
      }
      calls.uploadedRequestIds.add(requestId);
    },
    uploadMask: ({required requestId, required mask}) async =>
        calls.uploadedMasks.add((requestId: requestId, mask: mask)),
    requestGeneration:
        ({required requestId, required maskSource, required onCompletedStage}) {
          calls.requestedRequestIds.add(requestId);
          calls.requestedMaskSources.add(maskSource);
          onCompletedStage(completedStage: GenerationStage.cutout);
          return requestGeneration(requestId: requestId);
        },
    fetchGeneration: ({required requestId}) {
      calls.fetchedRequestIds.add(requestId);
      return fetchGeneration(requestId: requestId);
    },
    logEvent: ({required event, required parameters}) async =>
        calls.loggedEvents.add((event: event, parameters: parameters)),
  );
}

/// 生成時にその場で作った定義 (`definitions/{definitionId}`) の見本。見本の定義に無い属性と技を 1 つずつ持つ。
const Map<String, dynamic> waxDefinitionJson = {
  'version': 1,
  'elementTypes': [
    {'id': 'dynamic-wax', 'displayName': 'ろう', 'description': 'ろうでできた物'},
  ],
  'moves': [
    {
      'id': 'dynamic-wax-1',
      'displayName': 'ろうアタック',
      'elementTypeId': 'dynamic-wax',
      'power': 40,
      'powerPoints': 30,
      'category': 'attack',
      'effectId': 'metal_particle',
      'learnableLevelMinimum': 1,
      'learnableLevelMaximum': 30,
    },
  ],
};

/// [waxDefinitionJson] の定義の ID。
const String waxDefinitionId = 'definition-wax';

/// [base] (見本の定義) に [waxDefinitionJson] を足した定義。
MasterData definitionsWithWax({required MasterData base}) => mergeMasterData(
  base: base,
  additional: MasterData.fromJson(json: waxDefinitionJson),
);

/// サーバーで生まれたモンスターの見本。属性と最初の技は [waxDefinitionJson] にだけある。
/// 切り出した画像は持たない (widget test で Storage を読ませないため)。
OwnedMonster generatedWaxMonster({required String monsterId}) => OwnedMonster(
  definition: MonsterDefinition(
    id: monsterId,
    sourcePhotoReference: 'users/uid-1/photos/request-1',
    name: 'ロウソクン',
    encyclopediaText: 'あかりをともすと元気になる',
    elementTypeIds: const ['dynamic-wax'],
    learnset: const [
      LearnsetEntry(moveId: 'dynamic-wax-1', unlockLevel: 1),
      LearnsetEntry(moveId: 'metal_1', unlockLevel: 1),
    ],
    baseStats: const MonsterStats(
      hitPoints: 80,
      attack: 80,
      defense: 80,
      speed: 80,
    ),
    individualValues: const MonsterStats(
      hitPoints: 10,
      attack: 10,
      defense: 10,
      speed: 10,
    ),
    statCalculationVersion: 1,
    masterVersion: 1,
  ),
  level: 1,
  artPath: null,
  definitionIds: const [waxDefinitionId],
);
