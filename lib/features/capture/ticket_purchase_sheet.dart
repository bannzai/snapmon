import 'dart:async';

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../analytics/analytics_events.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import 'monster_generator.dart';

/// 購入の後に webhook の反映を待ってから「反映を待っています」の案内を出すまでの時間。
/// webhook は購入の直後に届くため、待たされたと感じる前に案内へ切り替える長さにした (実測はまだ無い。解放の前の sandbox で確かめる)。
const Duration _ticketArrivalNoticeDelay = Duration(seconds: 20);

/// 売っている package があれば購入画面を出し、生成をやり直してよいかを返す。
/// 売っていない間と package を読めない時は何も出さずに false を返す (今までの上限のエラーの表示のままにするため)。
Future<bool> offerTicketPurchase({
  required BuildContext context,
  required MonsterGenerator monsterGenerator,
}) async {
  final packages = await monsterGenerator.fetchTicketPackages().catchError(
    (Object _) => const <Package>[],
  );
  if (packages.isEmpty || !context.mounted) {
    return false;
  }
  return showTicketPurchaseSheet(
    context: context,
    packages: packages,
    purchaseTicketPackage: monsterGenerator.purchaseTicketPackage,
    watchGenerationTickets: monsterGenerator.watchGenerationTickets,
    logEvent: monsterGenerator.logEvent,
  );
}

/// [packages] の購入画面を出し、残高が増えた後に利用者が生成を続けると決めた時に true を返す。閉じた時は false。
/// 関数を個別に受け取るのは、開発者メニューが見本の package と見本の購入でこの画面を開くため。
Future<bool> showTicketPurchaseSheet({
  required BuildContext context,
  required List<Package> packages,
  required Future<TicketPurchaseResult> Function({required Package package})
  purchaseTicketPackage,
  required Stream<int> Function() watchGenerationTickets,
  required Future<void> Function({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  })
  logEvent,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TicketPurchaseSheet(
        packages: packages,
        purchaseTicketPackage: purchaseTicketPackage,
        watchGenerationTickets: watchGenerationTickets,
        logEvent: logEvent,
      ),
    ) ??
    false;

/// 生成チケットの購入画面。
class _TicketPurchaseSheet extends StatefulWidget {
  /// 購入画面を作る。
  const _TicketPurchaseSheet({
    required this.packages,
    required this.purchaseTicketPackage,
    required this.watchGenerationTickets,
    required this.logEvent,
  });

  /// 出す package (ストアの順)。
  final List<Package> packages;

  /// [MonsterGenerator.purchaseTicketPackage] と同じ形。
  final Future<TicketPurchaseResult> Function({required Package package})
  purchaseTicketPackage;

  /// [MonsterGenerator.watchGenerationTickets] と同じ形。
  final Stream<int> Function() watchGenerationTickets;

  /// [MonsterGenerator.logEvent] と同じ形。
  final Future<void> Function({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  })
  logEvent;

  @override
  State<_TicketPurchaseSheet> createState() => _TicketPurchaseSheetState();
}

/// [_TicketPurchaseSheet] の購入の進み具合と残高。
class _TicketPurchaseSheetState extends State<_TicketPurchaseSheet> {
  /// 残高の購読。購入の前から持つ (購入と webhook の反映の順を問わず、増えたのを逃さないため)。
  StreamSubscription<int>? _generationTicketsSubscription;

  /// 最後に読めた残高。
  int _generationTickets = 0;

  /// ストアの購入の途中か。
  bool _isPurchasing = false;

  /// ストアの購入が済んだか。
  bool _hasPurchased = false;

  /// 反映に時間がかかっている案内を出すか。
  bool _isTicketArrivalDelayed = false;

  /// 最後の購入の失敗。
  Object? _purchaseError;

  /// [_isTicketArrivalDelayed] にするタイマー。
  Timer? _ticketArrivalNoticeTimer;

  @override
  void initState() {
    super.initState();
    _generationTicketsSubscription = widget.watchGenerationTickets().listen(
      (generationTickets) =>
          setState(() => _generationTickets = generationTickets),
    );
    _logTicketPurchase(step: TicketPurchaseStep.shown, package: null);
  }

  @override
  void dispose() {
    _ticketArrivalNoticeTimer?.cancel();
    unawaited(_generationTicketsSubscription?.cancel());
    super.dispose();
  }

  /// 購入の段階 [step] を送る。計測の失敗は画面の進み方に影響させない。
  void _logTicketPurchase({
    required TicketPurchaseStep step,
    required Package? package,
  }) => unawaited(
    widget
        .logEvent(
          event: AnalyticsEvent.ticketPurchase,
          parameters: {
            'step': step.stepName,
            if (package != null) 'product': package.storeProduct.identifier,
          },
        )
        .catchError((Object _) {}),
  );

  /// [package] を購入し、結果に応じて画面を進める。
  Future<void> _purchase({required Package package}) async {
    setState(() {
      _isPurchasing = true;
      _purchaseError = null;
    });
    try {
      final result = await widget.purchaseTicketPackage(package: package);
      if (!mounted) {
        return;
      }
      switch (result) {
        case TicketPurchaseResult.purchased:
          _logTicketPurchase(
            step: TicketPurchaseStep.purchased,
            package: package,
          );
          _ticketArrivalNoticeTimer = Timer(_ticketArrivalNoticeDelay, () {
            setState(() => _isTicketArrivalDelayed = true);
          });
          setState(() {
            _isPurchasing = false;
            _hasPurchased = true;
          });
        case TicketPurchaseResult.cancelled:
          _logTicketPurchase(
            step: TicketPurchaseStep.cancelled,
            package: package,
          );
          setState(() => _isPurchasing = false);
      }
    } catch (error) {
      _logTicketPurchase(step: TicketPurchaseStep.failed, package: package);
      if (mounted) {
        setState(() {
          _isPurchasing = false;
          _purchaseError = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_isPurchasing,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _hasPurchased
                ? _purchasedChildren(l10n: l10n)
                : [
                    Text(
                      l10n.ticketPurchaseTitle,
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.hero,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.ticketPurchaseDescription,
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.body,
                    ),
                    const SizedBox(height: 16),
                    for (final package in widget.packages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton(
                          onPressed: _isPurchasing
                              ? null
                              : () => _purchase(package: package),
                          child: Text(
                            '${package.storeProduct.title}  ${package.storeProduct.priceString}',
                          ),
                        ),
                      ),
                    if (_purchaseError case final purchaseError?)
                      Text(
                        purchaseError.toString(),
                        textAlign: TextAlign.center,
                        style: SnapmonTextStyles.body.copyWith(
                          color: SnapmonColors.hitPointsLoss,
                        ),
                      ),
                    if (_isPurchasing)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
          ),
        ),
      ),
    );
  }

  /// 購入が済んだ後の表示。残高が増えるまでは待っている旨を、増えたら生成を続けるボタンを出す。
  List<Widget> _purchasedChildren({required AppLocalizations l10n}) =>
      _generationTickets > 0
      ? [
          Text(
            l10n.ticketPurchaseArrivedTitle,
            textAlign: TextAlign.center,
            style: SnapmonTextStyles.hero,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.ticketBalance(_generationTickets),
            textAlign: TextAlign.center,
            style: SnapmonTextStyles.body,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.ticketPurchaseContinue),
          ),
        ]
      : [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            _isTicketArrivalDelayed
                ? l10n.ticketPurchaseArrivalDelayed
                : l10n.ticketPurchaseWaiting,
            textAlign: TextAlign.center,
            style: SnapmonTextStyles.body,
          ),
        ];
}

/// 撮るタブの生成チケットの残高。売っている package があり、残高が正の時だけ出す (閉じている間の見え方を変えないため。Web は売っていない)。
class GenerationTicketBalance extends StatefulWidget {
  /// 残高の表示を作る。
  const GenerationTicketBalance({super.key, required this.monsterGenerator});

  /// 売っている package と残高の読み出し。
  final MonsterGenerator monsterGenerator;

  @override
  State<GenerationTicketBalance> createState() =>
      _GenerationTicketBalanceState();
}

/// [GenerationTicketBalance] の読み出し。作り直しのたびに読み直さないため State に持つ。
class _GenerationTicketBalanceState extends State<GenerationTicketBalance> {
  /// 売っている package の読み出し。読めない時は売っていない時と同じく出さない。
  late final Future<List<Package>> _packages = widget.monsterGenerator
      .fetchTicketPackages()
      .catchError((Object _) => const <Package>[]);

  /// 残高。
  late final Stream<int> _generationTickets = widget.monsterGenerator
      .watchGenerationTickets();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Package>>(
    future: _packages,
    builder: (context, packagesSnapshot) =>
        packagesSnapshot.data?.isNotEmpty ?? false
        ? StreamBuilder<int>(
            stream: _generationTickets,
            builder: (context, snapshot) => (snapshot.data ?? 0) > 0
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      context.l10n.ticketBalance(snapshot.data!),
                      style: SnapmonTextStyles.label,
                    ),
                  )
                : const SizedBox.shrink(),
          )
        : const SizedBox.shrink(),
  );
}

/// 設定画面の「購入の状態を同期する」。売っている package がある時だけ出す (閉じている間の見え方を変えないため)。
class TicketPurchaseSyncTile extends StatefulWidget {
  /// 項目を作る。
  const TicketPurchaseSyncTile({super.key, required this.monsterGenerator});

  /// 売っている package の読み出しと同期と計測。
  final MonsterGenerator monsterGenerator;

  @override
  State<TicketPurchaseSyncTile> createState() => _TicketPurchaseSyncTileState();
}

/// [TicketPurchaseSyncTile] の売っている package と同期の途中かどうか。
class _TicketPurchaseSyncTileState extends State<TicketPurchaseSyncTile> {
  /// 売っている package の読み出し。読めない時は売っていない時と同じく項目を出さない。
  late final Future<List<Package>> _packages = widget.monsterGenerator
      .fetchTicketPackages()
      .catchError((Object _) => const <Package>[]);

  /// 同期の途中か。
  bool _isSyncing = false;

  /// 同期し、結果を画面の下に出す。
  Future<void> _sync() async {
    final messenger = ScaffoldMessenger.of(context);
    final syncedMessage = context.l10n.ticketPurchaseSynced;
    setState(() => _isSyncing = true);
    try {
      await widget.monsterGenerator.syncTicketPurchases();
      unawaited(
        widget.monsterGenerator
            .logEvent(
              event: AnalyticsEvent.ticketPurchase,
              parameters: {'step': TicketPurchaseStep.restored.stepName},
            )
            .catchError((Object _) {}),
      );
      messenger.showSnackBar(SnackBar(content: Text(syncedMessage)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Package>>(
    future: _packages,
    builder: (context, snapshot) => snapshot.data?.isNotEmpty ?? false
        ? ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: Text(context.l10n.ticketPurchaseSync),
            enabled: !_isSyncing,
            onTap: _sync,
          )
        : const SizedBox.shrink(),
  );
}
