import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../analytics/analytics_events.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/square_icon_button.dart';
import '../dex/dex_store.dart';
import '../result/result_screen.dart';
import 'monster_generator.dart';

/// 生成の直後に図鑑の反映を待つ時間。Firestore のスナップショットは保存から 1 秒前後で届くため、通信が遅い時の余裕を見た値。
const Duration _monsterArrivalTimeout = Duration(seconds: 30);

/// 写真 1 枚から生成する画面。写真を整えて送り、段階ごとの待ち時間を出し、結果に応じて生まれた画面を開くか、
/// 判定待ち・生成しなかった理由・エラーを出す。生まれた画面を閉じたら、その画面の [ResultScreenAction] を返して閉じる。
class GenerationScreen extends StatefulWidget {
  /// 生成の画面を作る。
  const GenerationScreen({
    super.key,
    required this.sourcePhoto,
    required this.photoSource,
    required this.monsterGenerator,
    required this.dexStore,
  });

  /// 撮った・選んだ写真の中身。
  final Uint8List sourcePhoto;

  /// 写真がどこから来たか。
  final GenerationPhotoSource photoSource;

  /// 生成の呼び出しと計測。
  final MonsterGenerator monsterGenerator;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

/// 生成の画面の状態。
enum _GenerationPhase {
  /// 写真を整えている・送っている・サーバーが処理している。
  inProgress,

  /// サーバーが判定を待っている (pending_judge) か、まだ処理している。
  waiting,

  /// 写真から生成しなかった・生成に失敗した。
  notGenerated,

  /// 呼び出しが例外で終わった。
  error,
}

class _GenerationScreenState extends State<GenerationScreen> {
  /// 写真 1 枚に 1 つの要求 ID。送り直し・読み直しにも同じ ID を使う ([MonsterGenerator.createRequestId])。
  late final String _requestId = widget.monsterGenerator.createRequestId();

  Uint8List? _preparedPhoto;
  bool _isUploaded = false;
  GenerationStage? _completedStage;
  _GenerationPhase _phase = _GenerationPhase.inProgress;
  GenerationResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // 画面に入る前に setState を呼ばないため、最初のフレームの後に始める
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  /// 済んでいない手順 (写真を整える・送る) から生成を進める。もう一度試す時も同じ要求 ID で呼び直す。
  Future<void> _generate() async {
    setState(() {
      _phase = _GenerationPhase.inProgress;
      _error = null;
    });
    try {
      final preparedPhoto =
          _preparedPhoto ??
          await widget.monsterGenerator.preparePhoto(
            sourceBytes: widget.sourcePhoto,
          );
      if (!mounted) {
        return;
      }
      setState(() => _preparedPhoto = preparedPhoto);
      if (!_isUploaded) {
        await widget.monsterGenerator.uploadPhoto(
          requestId: _requestId,
          photo: preparedPhoto,
        );
        _isUploaded = true;
      }
      await _handleResult(
        result: await widget.monsterGenerator.requestGeneration(
          requestId: _requestId,
          onCompletedStage: ({required completedStage}) {
            if (mounted) {
              setState(() => _completedStage = completedStage);
            }
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _GenerationPhase.error;
          _error = error;
          // サーバーが写真を見つけられなかった (受け付けを断られた写真を消した) 時は、次に試す時に置き直す
          if (error is GenerationPhotoMissingException) {
            _isUploaded = false;
          }
        });
      }
    }
  }

  /// 判定待ちの生成の結果を読み直す。
  Future<void> _fetchAgain() async {
    setState(() {
      _phase = _GenerationPhase.inProgress;
      _error = null;
    });
    try {
      await _handleResult(
        // 同じ写真の別の要求の結果を使い回した時は、送った ID のレコードは無く、使い回し先の ID のレコードを読む
        result: await widget.monsterGenerator.fetchGeneration(
          requestId: _result?.requestId ?? _requestId,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _GenerationPhase.error;
          _error = error;
        });
      }
    }
  }

  /// [result] に応じて、生まれた画面を開くか、判定待ち・生成しなかった理由を出す。
  Future<void> _handleResult({required GenerationResult result}) async {
    if (!mounted) {
      return;
    }
    setState(() => _result = result);
    switch (result.status) {
      case GenerationStatus.saved || GenerationStatus.duplicate:
        // 同じ写真の別の要求の結果を使い回した時は、送った要求 ID と違う ID が返る (functions/src/generation/pipeline.ts)。
        // その時と同じ被写体 (duplicate) の時は、新しく生まれず図鑑にいるモンスターを開く
        final isNewlyBorn =
            result.status == GenerationStatus.saved &&
            result.requestId == _requestId;
        final monster = await widget.dexStore.waitForMonster(
          monsterId: result.monsterId!,
          timeout: _monsterArrivalTimeout,
        );
        if (isNewlyBorn) {
          await widget.monsterGenerator
              .logEvent(
                event: AnalyticsEvent.monsterGenerated,
                parameters: {'source': widget.photoSource.name},
              )
              // 計測の失敗は生まれた画面の表示に影響させない
              .catchError((Object _) {});
        }
        if (!mounted) {
          return;
        }
        final action = await Navigator.of(context).push(
          MaterialPageRoute<ResultScreenAction>(
            builder: (context) => ResultScreen(
              monster: monster,
              dexStore: widget.dexStore,
              origin: isNewlyBorn
                  ? ResultScreenOrigin.newlyBorn
                  : ResultScreenOrigin.alreadyInDex,
            ),
          ),
        );
        if (mounted) {
          Navigator.of(context).pop(action);
        }
      case GenerationStatus.processing || GenerationStatus.pendingJudge:
        setState(() => _phase = _GenerationPhase.waiting);
      case GenerationStatus.rejected || GenerationStatus.failed:
        setState(() => _phase = _GenerationPhase.notGenerated);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            children: [
              SquareIconButton(
                icon: Icons.close,
                tooltip: '閉じる',
                onPressed: () => Navigator.of(context).pop(),
                size: 44,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox.square(
              dimension: 200,
              child: ClipRRect(
                borderRadius: SnapmonRadii.card,
                child: Image.memory(
                  _preparedPhoto ?? widget.sourcePhoto,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // 整える前の写真が読めない形式 (HEIC 等) でも、画面は壊さず枠だけを出す
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(color: SnapmonColors.surfaceRaised),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          ..._buildPhaseContent(),
        ],
      ),
    ),
  );

  List<Widget> _buildPhaseContent() => switch (_phase) {
    _GenerationPhase.inProgress => [
      Text(
        _inProgressText(),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 24),
      const Center(child: CircularProgressIndicator()),
    ],
    _GenerationPhase.waiting => [
      const Text(
        'もう少し待ってね',
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      const Text(
        'モンスターの属性を決めるのに時間がかかっています\n生まれたら図鑑に入ります',
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 28),
      FilledButton(onPressed: _fetchAgain, child: const Text('もう一度確かめる')),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('あとで見る'),
      ),
    ],
    _GenerationPhase.notGenerated => [
      const Text(
        '生まれませんでした',
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        _notGeneratedText(result: _result!),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body,
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('撮り直す'),
      ),
    ],
    _GenerationPhase.error => [
      const Text(
        '生成できませんでした',
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      const SizedBox(height: 12),
      Text(
        _error.toString(),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.body.copyWith(
          color: SnapmonColors.hitPointsLoss,
        ),
      ),
      const SizedBox(height: 28),
      FilledButton(onPressed: _generate, child: const Text('もう一度試す')),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('もどる'),
      ),
    ],
  };

  /// 進めている手順の文言。サーバーの段階は最後に済んだ段階 ([_completedStage]) の次の手順を出す。
  String _inProgressText() {
    if (_preparedPhoto == null) {
      return '写真を整えています';
    }
    if (!_isUploaded) {
      return '写真を送っています';
    }
    return switch (_completedStage) {
      null || GenerationStage.uploaded => '写真を確かめています',
      GenerationStage.safesearch => '被写体を切り出しています',
      GenerationStage.cutout => '名前と図鑑の文章を考えています',
      GenerationStage.claude ||
      GenerationStage.classify ||
      GenerationStage.dedupe => '属性と技を決めています',
      GenerationStage.judge || GenerationStage.saved => 'モンスターが生まれます',
    };
  }

  /// 生成しなかった・失敗した [result] の理由の文言。
  static String _notGeneratedText({required GenerationResult result}) =>
      switch (result.rejectionReason) {
        GenerationRejectionReason.explicitContent => 'この写真からはモンスターを作れません',
        GenerationRejectionReason.faceDetected ||
        GenerationRejectionReason.personDetected =>
          '人が写っている写真からは作れません\n物だけを撮ってください',
        GenerationRejectionReason.noSubject =>
          '被写体が見つかりませんでした\n物を大きく写して撮ってください',
        GenerationRejectionReason.inappropriateText ||
        GenerationRejectionReason.refused => 'うまく作れませんでした\nもう一度撮ってみてください',
        null => '生成に失敗しました\nもう一度撮ってみてください',
      };
}
