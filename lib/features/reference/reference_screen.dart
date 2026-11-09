import 'package:flutter/material.dart';

import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../dex/dex_store.dart';
import 'move_detail_screen.dart';

/// 属性の相性表と技の一覧の画面。図鑑の画面から開き、上のタブで相性表と技の一覧を切り替える。
/// 描くのは図鑑の定義 ([DexStore.definitions]。最新の版の master に、図鑑のモンスターが参照するその場で作った定義を足したもの)。
/// 開いた時に定義を最新の master から読み直す (相性表はバトルと同じく最新の版を見せるため。documents/adr/0001-tech-stack.md)。
class ReferenceScreen extends StatefulWidget {
  /// 相性表と技の一覧の画面を作る。
  const ReferenceScreen({super.key, required this.dexStore});

  /// 定義を引く図鑑。
  final DexStore dexStore;

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

/// [ReferenceScreen] の状態。開いた時の最新の master の読み直しを持つ。
class _ReferenceScreenState extends State<ReferenceScreen> {
  /// 最新の master の読み直し。終わるまでは表を描かない (古い版の相性を最新と読ませないため)。
  late Future<void> _refreshDefinitions = widget.dexStore.refreshDefinitions();

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.referenceTitle),
        bottom: TabBar(
          tabs: [
            Tab(text: context.l10n.referenceTypeChartTab),
            Tab(text: context.l10n.referenceMovesTab),
          ],
        ),
      ),
      body: FutureBuilder<void>(
        future: _refreshDefinitions,
        builder: (context, snapshot) => switch (snapshot) {
          AsyncSnapshot(connectionState: != ConnectionState.done) =>
            const Center(child: CircularProgressIndicator()),
          AsyncSnapshot(:final error?) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error.toString(),
                    key: const Key('reference-error'),
                    textAlign: TextAlign.center,
                    style: SnapmonTextStyles.body.copyWith(
                      color: SnapmonColors.hitPointsLoss,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _refreshDefinitions = widget.dexStore
                          .refreshDefinitions();
                    }),
                    child: Text(context.l10n.dexReload),
                  ),
                ],
              ),
            ),
          ),
          _ => ListenableBuilder(
            listenable: widget.dexStore,
            builder: (context, _) => TabBarView(
              children: [
                _TypeChart(definitions: widget.dexStore.definitions),
                _MoveList(definitions: widget.dexStore.definitions),
              ],
            ),
          ),
        },
      ),
    ),
  );
}

/// 相性表の 1 マスの幅。「プラスチック」のような長い属性の名前は 2 行に折り返し、横に並ぶ数を増やすため狭めにした。
const double _typeChartCellWidth = 56;

/// 相性表の左の列 (技の属性) の幅。左上の角の文言 (「技 ／ 受ける」) が 2 行に収まる幅にした。
const double _typeChartHeaderColumnWidth = 84;

/// 相性表の 1 マスの高さ。2 行に折り返した属性の名前が入る高さにした。
const double _typeChartCellHeight = 40;

/// 属性 × 属性の相性表。縦が技の属性、横が受ける側の属性で、倍率を数字と色 (よく効くはアクセント、効きにくいは HP の減りの色) で描く。
/// 属性が多く画面の幅に収まらないため、横にスクロールさせる。
class _TypeChart extends StatelessWidget {
  const _TypeChart({required this.definitions});

  /// 行・列に並べる属性と、マスの倍率を引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) {
    final elementTypes = definitions.elementTypes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          context.l10n.referenceTypeChartNote,
          style: SnapmonTextStyles.small,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(_typeChartCellWidth),
            columnWidths: const {
              0: FixedColumnWidth(_typeChartHeaderColumnWidth),
            },
            border: TableBorder.all(color: SnapmonColors.background, width: 2),
            children: [
              TableRow(
                children: [
                  _TypeChartCell(
                    color: SnapmonColors.background,
                    child: Text(
                      context.l10n.referenceTypeChartCorner,
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.small,
                    ),
                  ),
                  for (final defenderElementType in elementTypes)
                    _TypeChartElementHeader(
                      elementTypeId: defenderElementType.id,
                      displayName: defenderElementType.displayName,
                    ),
                ],
              ),
              for (final attackerElementType in elementTypes)
                TableRow(
                  children: [
                    _TypeChartElementHeader(
                      elementTypeId: attackerElementType.id,
                      displayName: attackerElementType.displayName,
                    ),
                    for (final defenderElementType in elementTypes)
                      _TypeChartMultiplierCell(
                        key: Key(
                          'type-chart-${attackerElementType.id}-${defenderElementType.id}',
                        ),
                        multiplier: definitions.typeMultiplier(
                          attackerElementTypeId: attackerElementType.id,
                          defenderElementTypeId: defenderElementType.id,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 相性表の 1 マスの枠。
class _TypeChartCell extends StatelessWidget {
  const _TypeChartCell({required this.color, required this.child});

  /// マスの地の色。
  final Color color;

  /// マスの中身。
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    height: _typeChartCellHeight,
    color: color,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    child: child,
  );
}

/// 相性表の見出しの属性のマス (属性の色の地に名前)。
class _TypeChartElementHeader extends StatelessWidget {
  const _TypeChartElementHeader({
    required this.elementTypeId,
    required this.displayName,
  });

  /// 見出しの属性の ID。地の色を決める。
  final String elementTypeId;

  /// 見出しに出す属性の名前。
  final String displayName;

  @override
  Widget build(BuildContext context) => _TypeChartCell(
    color: elementTypeColor(elementTypeId: elementTypeId),
    child: Text(
      displayName,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: SnapmonTextStyles.small.copyWith(
        color: SnapmonColors.textOnBackground,
        height: 1.2,
      ),
    ),
  );
}

/// 相性表の倍率のマス。
class _TypeChartMultiplierCell extends StatelessWidget {
  const _TypeChartMultiplierCell({super.key, required this.multiplier});

  /// マスの相性の倍率 (相性表の値)。
  final double multiplier;

  @override
  Widget build(BuildContext context) => _TypeChartCell(
    color: multiplier > 1
        ? SnapmonColors.accent
        : multiplier < 1
        ? SnapmonColors.hitPointsLoss
        : SnapmonColors.surface,
    child: Text(
      formatTypeMultiplier(multiplier: multiplier),
      style: SnapmonTextStyles.label.copyWith(
        color: multiplier == 1
            ? SnapmonColors.textMuted
            : SnapmonColors.textOnCard,
      ),
    ),
  );
}

/// 技の一覧。属性ごとに技を並べ、タップで技の詳細 ([openMoveDetail]) を開く。
/// 別の技が置き換えた補助技 (`Move.replacesMoveId` が指す技) は、新しく生まれるモンスターが覚えないため並べない (#257)。
class _MoveList extends StatelessWidget {
  const _MoveList({required this.definitions});

  /// 並べる属性と技、技の詳細で引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) => _buildList(
    replacedMoveIds: {
      for (final move in definitions.moves)
        if (move.replacesMoveId case final String replacedMoveId)
          replacedMoveId,
    },
  );

  /// [replacedMoveIds] に入っていない技を属性ごとに並べた一覧を返す。
  Widget _buildList({required Set<String> replacedMoveIds}) => ListView(
    key: const Key('reference-move-list'),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      for (final elementType in definitions.elementTypes) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              ElementTypeTag(
                elementTypeId: elementType.id,
                definitions: definitions,
              ),
            ],
          ),
        ),
        for (final move in definitions.moves)
          if (move.elementTypeId == elementType.id &&
              !replacedMoveIds.contains(move.id))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MoveRow(move: move, definitions: definitions),
            ),
      ],
    ],
  );
}

/// 技の一覧の 1 行 (名前・威力・PP・覚えるレベル・特殊効果の短い説明)。
class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.move, required this.definitions});

  /// 行に出す技。
  final Move move;

  /// 技の詳細で属性の名前と相性を引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) => Material(
    color: SnapmonColors.card,
    borderRadius: SnapmonRadii.button,
    child: InkWell(
      key: Key('reference-move-${move.id}'),
      borderRadius: SnapmonRadii.button,
      onTap: () => openMoveDetail(
        context: context,
        move: move,
        definitions: definitions,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    move.displayName,
                    style: SnapmonTextStyles.label.copyWith(
                      color: SnapmonColors.textOnCard,
                    ),
                  ),
                  Text(
                    context.l10n.referenceMoveSummary(
                      move.power,
                      move.powerPoints,
                      move.learnableLevelMinimum,
                    ),
                    style: SnapmonTextStyles.small.copyWith(
                      color: SnapmonColors.textOnCardMuted,
                    ),
                  ),
                  if (move.specialEffect case final specialEffect?)
                    Text(
                      specialEffect.summary,
                      style: SnapmonTextStyles.small.copyWith(
                        color: SnapmonColors.textOnCard,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: SnapmonColors.textOnCardMuted,
            ),
          ],
        ),
      ),
    ),
  );
}
