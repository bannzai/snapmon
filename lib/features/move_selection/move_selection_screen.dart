import 'package:flutter/material.dart';

import '../../common_ui/square_icon_button.dart';
import '../../domain/battle/battle_engine.dart';
import '../../l10n/l10n.dart';
import '../../monster_ui/move_card.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../reference/move_detail_screen.dart';

/// 対戦で使う技 (技の枠) を、モンスターが持っている技 ([availableMoveIDs]) から選ぶ画面 (#309)。
/// 技をタップした順に枠の番号が付き、その順でバトルの技のボタンに並ぶ。決定すると [DexStore.selectMoves] で保存して閉じる。
class MoveSelectionScreen extends StatefulWidget {
  /// 技を選ぶ画面を作る。
  const MoveSelectionScreen({
    super.key,
    required this.monster,
    required this.dexStore,
  });

  /// 技を選ぶモンスター。
  final OwnedMonster monster;

  /// 選んだ技を保存する図鑑 (技の定義も引く)。
  final DexStore dexStore;

  @override
  State<MoveSelectionScreen> createState() => _MoveSelectionScreenState();
}

class _MoveSelectionScreenState extends State<MoveSelectionScreen> {
  /// 選んでいる技の ID (枠の順)。開いた時は今の技の枠。
  late List<String> _selectedMoveIDs = equippedLearnsetEntries(
    learnset: widget.monster.definition.learnset,
    actionCardMoveIDs: widget.monster.actionCardMoveIDs,
    selectedMoveIDs: widget.monster.selectedMoveIDs,
    level: widget.monster.level,
  );

  /// 保存の途中か。途中は決定を押せない。
  bool _isSaving = false;

  /// [moveID] を選んでいれば外し、選んでいなければ空いている最後の枠に入れる。枠が埋まっている時は何もしない。
  void _toggle({required String moveID}) {
    setState(() {
      if (_selectedMoveIDs.contains(moveID)) {
        _selectedMoveIDs = [
          for (final selectedMoveID in _selectedMoveIDs)
            if (selectedMoveID != moveID) selectedMoveID,
        ];
      } else if (_selectedMoveIDs.length < maximumEquippedMoveCount) {
        _selectedMoveIDs = [..._selectedMoveIDs, moveID];
      }
    });
  }

  /// 選んだ技を保存して閉じる。保存に失敗したらエラーをそのまま出して画面に留まる。
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _isSaving = true);
    try {
      await widget.dexStore.selectMoves(
        monsterID: widget.monster.definition.id,
        moveIDs: _selectedMoveIDs,
      );
      navigator.pop();
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final monster = widget.monster;
    final definitions = widget.dexStore.definitions;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  SquareIconButton(
                    icon: Icons.chevron_left,
                    // AppBar の戻るボタンと同じ文言 (Material の各言語の訳) にする
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    size: 44,
                  ),
                  Expanded(
                    child: Text(
                      context.l10n.moveSelectionTitle(monster.definition.name),
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.label.copyWith(
                        color: SnapmonColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.l10n.moveSelectionDescription(maximumEquippedMoveCount),
                textAlign: TextAlign.center,
                style: SnapmonTextStyles.small,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                children: [
                  for (final moveID in availableMoveIDs(
                    learnset: monster.definition.learnset,
                    actionCardMoveIDs: monster.actionCardMoveIDs,
                    level: monster.level,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SelectableMoveRow(
                        key: Key('move-selection-$moveID'),
                        moveID: moveID,
                        slotIndex: _selectedMoveIDs.indexOf(moveID),
                        dexStore: widget.dexStore,
                        onTap: () => _toggle(moveID: moveID),
                        onLongPress: () => openMoveDetail(
                          context: context,
                          move: definitions.moveByID(moveID: moveID),
                          definitions: definitions,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('move-selection-reset'),
                      onPressed: _selectedMoveIDs.isEmpty || _isSaving
                          ? null
                          : () => setState(() => _selectedMoveIDs = []),
                      child: Text(context.l10n.moveSelectionReset),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // 技の枠が空のまま戦えないため、1 つも選んでいない間は押せない
                    child: FilledButton(
                      key: const Key('move-selection-save'),
                      onPressed: _selectedMoveIDs.isEmpty || _isSaving
                          ? null
                          : _save,
                      child: Text(context.l10n.moveSelectionSave),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 持っている技 1 つの行。選んでいる技は枠の番号 (1 始まり) を左に出す。
class _SelectableMoveRow extends StatelessWidget {
  const _SelectableMoveRow({
    super.key,
    required this.moveID,
    required this.slotIndex,
    required this.dexStore,
    required this.onTap,
    required this.onLongPress,
  });

  /// 行の技の ID。
  final String moveID;

  /// 選んでいる枠の位置 (0 始まり)。選んでいなければ -1。
  final int slotIndex;

  /// 技の定義を引く図鑑。
  final DexStore dexStore;

  /// タップした時 (選ぶ・外す)。
  final VoidCallback onTap;

  /// 長押しした時 (技の詳細を開く)。
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isSelected = slotIndex >= 0;
    return Material(
      color: SnapmonColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: SnapmonRadii.button,
        side: BorderSide(
          color: isSelected ? SnapmonColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: SnapmonRadii.button,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? SnapmonColors.accent
                        : SnapmonColors.cardSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      isSelected ? '${slotIndex + 1}' : '',
                      key: Key('move-selection-slot-$moveID'),
                      style: SnapmonTextStyles.label.copyWith(
                        color: SnapmonColors.textOnCard,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MoveCard(
                  move: dexStore.definitions.moveByID(moveID: moveID),
                  remainingPowerPoints: null,
                  typeMultiplier: null,
                  definitions: dexStore.definitions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
