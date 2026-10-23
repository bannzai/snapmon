import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../analytics/analytics_events.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../age_gate/age_confirmation.dart';
import '../age_gate/age_gate_screen.dart';
import '../age_gate/age_verified_session_store.dart';
import '../capture/generation_screen.dart';
import '../capture/monster_generator.dart';
import '../dex/dex_store.dart';
import '../home/home_shell.dart';
import '../result/result_screen.dart';
import '../settings/settings_screen.dart';
import '../share/card_sharer.dart';

/// タイトル画面のボタン (計測の `title_action` の `action`)。
enum TitleAction {
  /// 写真から選んではじめる。
  album,

  /// カメラで撮ってはじめる。
  camera,

  /// つづきから (図鑑 N)。
  continueFromDex,
}

/// 起動後の最初の画面 (モックの documents/design/mock-2026-10-23/Title.dc.html)。世界観を 1 枚で見せ、
/// 写真から選ぶかカメラで撮るかで体験を始める。図鑑に 1 体以上いれば「つづきから」で下タブの画面に入る。
///
/// ログインが済んでいない時は、ボタンを押してから下タブ・生成に進む前にログインを済ませる。年齢の確認が済んでいれば
/// 画面を開いた時に裏でログインを始め、失敗はボタンを押した時に「つながりませんでした」と再試行で出す
/// (年齢の確認がまだなら、ボタンを押した時に年齢の確認から進める。年齢の確認は #44 で消える)。
class TitleScreen extends StatefulWidget {
  /// タイトル画面を作る。
  const TitleScreen({
    super.key,
    required this.dexStore,
    required this.ageConfirmationStore,
    required this.ageVerifiedSessionStore,
    required this.monsterGenerator,
    required this.cardSharer,
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
    required this.logEvent,
    required this.onEnterHome,
  });

  /// 図鑑と手持ち (「つづきから」の表示と数)。
  final DexStore dexStore;

  /// 年齢の確認。
  final AgeConfirmationStore ageConfirmationStore;

  /// ログインの状態。
  final AgeVerifiedSessionStore ageVerifiedSessionStore;

  /// 撮る・選ぶ・生成の呼び出しと計測。
  final MonsterGenerator monsterGenerator;

  /// 生まれた画面からの図鑑のカードの共有に使う関数の組。
  final CardSharer cardSharer;

  /// 利用規約・プライバシーポリシーを開く。
  final OpenUrl openUrl;

  /// ログインの失敗の画面に「ログインせずに進む (DEBUG)」を出すか ([AgeVerifiedSessionScreen.isDebugSkipEnabled])。
  final bool isDeveloperMenuEnabled;

  /// Analytics にイベントを送る ([logAnalyticsEvent] と同じ形)。
  final Future<void> Function({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  })
  logEvent;

  /// 下タブの画面を [tab] から開く。
  final void Function({required HomeTab tab}) onEnterHome;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  /// カメラのある端末か。分かるまでと Web は false (「カメラで撮ってはじめる」を出さない)。
  bool _hasCamera = false;

  /// ボタンの処理 (写真を選ぶ・ログイン・生成) の途中か。途中の二重押しを受け付けない。
  bool _isBusy = false;

  /// ログイン (計測の収集の開始) より前に起きたイベント。初回起動ではタイトルの表示とボタンの操作が年齢の確認・ログインより前に
  /// 起きるため、その場で送ると収集が始まっていなくて落ちる。ログインが済んだ時に順に送る (ログインに至らなければ送らない。
  /// 年齢の確認より前に識別子を使わない方針のため)。
  final List<({AnalyticsEvent event, Map<String, Object>? parameters})>
  _eventsBeforeSession = [];

  @override
  void initState() {
    super.initState();
    widget.ageVerifiedSessionStore.addListener(_flushEventsIfSessionStarted);
    unawaited(_detectCamera());
    // ログインの状態を変えるため、親の ListenableBuilder が build の途中にならない最初のフレームの後に始める
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startSessionInBackground());
      unawaited(_logEvent(event: AnalyticsEvent.titleShown, parameters: null));
    });
  }

  @override
  void dispose() {
    widget.ageVerifiedSessionStore.removeListener(_flushEventsIfSessionStarted);
    super.dispose();
  }

  /// イベントを送る。ログインが済んでいなければ [_eventsBeforeSession] に溜める。計測の失敗はタイトルの表示・体験の開始に影響させない。
  Future<void> _logEvent({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  }) async {
    if (!widget.ageVerifiedSessionStore.canEnterApp) {
      _eventsBeforeSession.add((event: event, parameters: parameters));
      return;
    }
    try {
      await widget.logEvent(event: event, parameters: parameters);
    } catch (_) {
      // 計測の失敗は無視する
    }
  }

  void _flushEventsIfSessionStarted() {
    if (!widget.ageVerifiedSessionStore.canEnterApp) {
      return;
    }
    final events = List.of(_eventsBeforeSession);
    _eventsBeforeSession.clear();
    unawaited(() async {
      for (final logged in events) {
        await _logEvent(event: logged.event, parameters: logged.parameters);
      }
    }());
  }

  Future<void> _detectCamera() async {
    if (kIsWeb) {
      return;
    }
    try {
      final hasCamera =
          (await widget.monsterGenerator.listCameras()).isNotEmpty;
      if (mounted) {
        setState(() => _hasCamera = hasCamera);
      }
    } catch (_) {
      // カメラの一覧を取れない端末は、カメラが無い端末と同じく写真から選ぶだけにする
    }
  }

  /// 年齢の確認が済んでいれば、タイトルを見ている間に裏でログインを進める。失敗はここでは出さず、ボタンを押した時に出す。
  Future<void> _startSessionInBackground() async {
    if (widget.ageConfirmationStore.status != AgeConfirmationStatus.allowed ||
        widget.ageVerifiedSessionStore.canEnterApp) {
      return;
    }
    await widget.ageVerifiedSessionStore.start(
      birthYear: widget.ageConfirmationStore.birthYear!,
      birthMonth: widget.ageConfirmationStore.birthMonth!,
    );
  }

  Future<void> _logAction({required TitleAction action}) => _logEvent(
    event: AnalyticsEvent.titleAction,
    parameters: {
      'action': switch (action) {
        TitleAction.album => 'album',
        TitleAction.camera => 'camera',
        TitleAction.continueFromDex => 'continue',
      },
    },
  );

  /// ボタンの処理 [work] を、途中の二重押しを受け付けずに実行する。例外はそのまま SnackBar に出す。
  Future<void> _run({required Future<void> Function() work}) async {
    if (_isBusy) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      await work();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// 下タブ・生成に進める状態 (ログイン済みか DEBUG で飛ばした) にする。裏のログインが途中なら終わるのを待ち、
  /// 済んでいなければ年齢の確認とログインの画面を開いて済むまで待つ。戻るで閉じられた時は false。
  Future<bool> _ensureCanEnterApp() async {
    final sessionStore = widget.ageVerifiedSessionStore;
    if (sessionStore.isStarting) {
      final completer = Completer<void>();
      void onChanged() {
        if (!sessionStore.isStarting && !completer.isCompleted) {
          completer.complete();
        }
      }

      sessionStore.addListener(onChanged);
      try {
        await completer.future;
      } finally {
        sessionStore.removeListener(onChanged);
      }
    }
    if (sessionStore.canEnterApp || !mounted) {
      return sessionStore.canEnterApp;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SessionGateScreen(
          ageConfirmationStore: widget.ageConfirmationStore,
          ageVerifiedSessionStore: sessionStore,
          isDebugSkipEnabled: widget.isDeveloperMenuEnabled,
        ),
      ),
    );
    return sessionStore.canEnterApp;
  }

  /// 写真から選んではじめる。選ばずに閉じた時はタイトルに留まる。生成の画面を閉じた後は、結果にかかわらず下タブの画面に進む
  /// (生まれたカードから手持ちに入れた時は図鑑、それ以外は撮る。撮る画面からの生成と同じ)。
  Future<void> _startFromAlbum() => _run(
    work: () async {
      await _logAction(action: TitleAction.album);
      final photo = await widget.monsterGenerator.pickAlbumPhoto();
      if (photo == null || !mounted || !await _ensureCanEnterApp()) {
        return;
      }
      if (!mounted) {
        return;
      }
      final action = await Navigator.of(context).push(
        MaterialPageRoute<ResultScreenAction>(
          builder: (context) => GenerationScreen(
            sourcePhoto: photo,
            photoSource: GenerationPhotoSource.album,
            monsterGenerator: widget.monsterGenerator,
            dexStore: widget.dexStore,
            cardSharer: widget.cardSharer,
          ),
        ),
      );
      if (mounted) {
        widget.onEnterHome(
          tab: action == ResultScreenAction.openDex
              ? HomeTab.dex
              : HomeTab.capture,
        );
      }
    },
  );

  /// [action] のボタンで、下タブの画面を [tab] から開く。
  Future<void> _enterHome({
    required TitleAction action,
    required HomeTab tab,
  }) => _run(
    work: () async {
      await _logAction(action: action);
      if (await _ensureCanEnterApp() && mounted) {
        widget.onEnterHome(tab: tab);
      }
    },
  );

  Future<void> _openUrl({required Uri uri}) async {
    try {
      if (!await widget.openUrl(uri: uri) && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$uri を開けませんでした')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  // 高さが足りない画面 (横向き・低い Web のウィンドウ) では全体をスクロールし、ボタンに必ず届くようにする。
  // 足りる時はヒーローが残りの高さを埋める
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: _Particles()),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: _buildContent()),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildContent() => Column(
    children: [
      const SizedBox(height: 40),
      const Text('snapmon', style: _TitleTextStyles.logo),
      const SizedBox(height: 10),
      const Text('SNAP IT  FIGHT IT', style: _TitleTextStyles.tagline),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          // ConstrainedBox のコンストラクタは const でない (assert を持つ)
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minimumHeroHeight),
            child: const _Hero(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          children: [
            _StartButton(
              key: const Key('title-album'),
              label: '写真から選んではじめる',
              icon: Icons.image_outlined,
              isPrimary: true,
              onPressed: _startFromAlbum,
            ),
            if (_hasCamera) ...[
              const SizedBox(height: 12),
              _StartButton(
                key: const Key('title-camera'),
                label: 'カメラで撮ってはじめる',
                icon: Icons.photo_camera_outlined,
                isPrimary: false,
                onPressed: () => _enterHome(
                  action: TitleAction.camera,
                  tab: HomeTab.capture,
                ),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
        child: Column(
          children: [
            ListenableBuilder(
              listenable: widget.dexStore,
              builder: (context, _) {
                final monsterCount = widget.dexStore.monsters.length;
                if (monsterCount == 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _FooterLink(
                    key: const Key('title-continue'),
                    label: 'つづきから (図鑑 $monsterCount)',
                    style: _TitleTextStyles.continueLink,
                    onTap: () => _enterHome(
                      action: TitleAction.continueFromDex,
                      tab: HomeTab.dex,
                    ),
                  ),
                );
              },
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$minimumAge 歳以上が対象 · ', style: _TitleTextStyles.footer),
                _FooterLink(
                  label: '利用規約',
                  style: _TitleTextStyles.footer,
                  onTap: () => _openUrl(uri: termsUri),
                ),
                const Text(' · ', style: _TitleTextStyles.footer),
                _FooterLink(
                  label: 'プライバシー',
                  style: _TitleTextStyles.footer,
                  onTap: () => _openUrl(uri: privacyPolicyUri),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// 高さが足りない画面でのヒーローの高さ。斜めの写真の枠 (236) が見出しと重ならない高さにした。
const double _minimumHeroHeight = 300;

/// タイトル画面だけで使う文字の大きさ (モックの Title.dc.html から取った)。
abstract final class _TitleTextStyles {
  /// ロゴ (モックの 44px)。
  static const TextStyle logo = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 44,
    height: 1,
    letterSpacing: 0.88,
    color: SnapmonColors.textOnBackground,
  );

  /// ロゴの下の英字のキャッチ (モックの 13px、字間 0.18em)。
  static const TextStyle tagline = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.34,
    color: SnapmonColors.accent,
  );

  /// ヒーローの下の見出し (モックの 24px)。
  static const TextStyle heading = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 24,
    height: 1.35,
    color: SnapmonColors.textOnBackground,
  );

  /// 「つづきから」。
  static const TextStyle continueLink = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 12,
    height: 1.8,
    fontWeight: FontWeight.w700,
    color: SnapmonColors.accent,
  );

  /// 対象年齢と規約のリンク。
  static const TextStyle footer = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 12,
    height: 1.8,
    color: SnapmonColors.textMuted,
  );
}

/// 体験の入口のボタン。主 (黄緑・60px) と副 (暗い地・56px)。
class _StartButton extends StatelessWidget {
  const _StartButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = isPrimary
        ? SnapmonColors.textOnCard
        : SnapmonColors.textOnBackground;
    return Material(
      color: isPrimary ? SnapmonColors.accent : SnapmonColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: SnapmonRadii.card,
        side: isPrimary
            ? BorderSide.none
            : const BorderSide(color: SnapmonColors.artBackground),
      ),
      child: InkWell(
        borderRadius: SnapmonRadii.card,
        onTap: onPressed,
        child: SizedBox(
          height: isPrimary ? 60 : 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: SnapmonTextStyles.buttonLarge.copyWith(
                  fontSize: isPrimary ? 17 : 16,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 画面の下の文字のリンク。
class _FooterLink extends StatelessWidget {
  const _FooterLink({
    super.key,
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: SnapmonRadii.tag,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(label, style: style),
    ),
  );
}

/// 地に散らした電気のような粒と、中央の淡い光 (モックの背景)。位置は画面に対する割合で置く。
class _Particles extends StatelessWidget {
  const _Particles();

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _ParticlesPainter()));
}

class _ParticlesPainter extends CustomPainter {
  /// 粒の位置 (モックの 390×844 に対する割合)・直径・不透明度・色。
  static const List<
    ({double x, double y, double size, double opacity, Color color})
  >
  _particles = [
    (
      x: 36 / 390,
      y: 150 / 844,
      size: 6,
      opacity: .8,
      color: SnapmonColors.accent,
    ),
    (
      x: 318 / 390,
      y: 196 / 844,
      size: 4,
      opacity: .6,
      color: SnapmonColors.accent,
    ),
    (
      x: 300 / 390,
      y: 470 / 844,
      size: 8,
      opacity: .5,
      color: SnapmonColors.accent,
    ),
    (
      x: 62 / 390,
      y: 500 / 844,
      size: 5,
      opacity: .7,
      color: SnapmonColors.accent,
    ),
    (
      x: 180 / 390,
      y: 120 / 844,
      size: 3,
      opacity: .5,
      color: SnapmonColors.textOnBackground,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width / 2, size.height * .42);
    canvas.drawCircle(
      glowCenter,
      size.width * .48,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                SnapmonColors.accent.withValues(alpha: .14),
                SnapmonColors.accent.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: glowCenter, radius: size.width * .48),
            ),
    );
    for (final particle in _particles) {
      canvas.drawCircle(
        Offset(size.width * particle.x, size.height * particle.y),
        particle.size / 2,
        Paint()..color = particle.color.withValues(alpha: particle.opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) => false;
}

/// ヒーロー: 元の写真を示す斜めの枠とファインダーの角の中で、切り出されたマグカップに目とオーラが付いたモンスターが浮かぶ。
/// 下に見出し。動くのは浮遊とオーラの 2 つだけで、端末の「視差効果を減らす」が有効な時は動かさない。
class _Hero extends StatefulWidget {
  const _Hero();

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  /// 浮遊とオーラの 1 往復の時間 (モックの 3.2s)。
  static const Duration _cycle = Duration(milliseconds: 3200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) =>
              CustomPaint(painter: _HeroPainter(progress: _progress.value)),
        ),
      ),
      const Align(
        alignment: Alignment.bottomCenter,
        child: Text(
          '身の回りの物が\nモンスターになって戦う',
          textAlign: TextAlign.center,
          style: _TitleTextStyles.heading,
        ),
      ),
    ],
  );
}

/// ヒーローの絵。[progress] (0〜1) で浮遊の高さとオーラの強さが変わる。寸法はモックの値 (390px 幅) をそのまま使う。
class _HeroPainter extends CustomPainter {
  const _HeroPainter({required this.progress});

  final double progress;

  /// マグカップの色 (モックは metal の属性の色)。
  static const Color _mugColor = Color(0xFF6D7B8A);

  /// マグカップの陰の色。
  static const Color _mugShadeColor = Color(0xFF55606E);

  /// 斜めの写真の枠の色と線。
  static const Color _photoColor = Color(0xFF231E30);
  static const Color _photoBorderColor = Color(0xFF2F293F);

  @override
  void paint(Canvas canvas, Size size) {
    // 見出し (2 行) の分だけ上に寄せた中心
    final center = Offset(size.width / 2, (size.height - 72) / 2);

    _paintPhotoFrame(canvas: canvas, center: center);
    _paintFinderCorners(
      canvas: canvas,
      size: Size(size.width, size.height - 72),
    );
    _paintAura(canvas: canvas, center: center);
    canvas.save();
    // 浮遊: 0〜-10px
    canvas.translate(center.dx - 85, center.dy - 85 - 10 * progress);
    _paintMonster(canvas: canvas);
    canvas.restore();
  }

  void _paintPhotoFrame({required Canvas canvas, required Offset center}) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-6 * math.pi / 180);
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-118, -118, 236, 236),
      const Radius.circular(20),
    );
    canvas.drawRRect(frame, Paint()..color = _photoColor);
    canvas.drawRRect(
      frame,
      Paint()
        ..color = _photoBorderColor
        ..style = PaintingStyle.stroke,
    );
    // 紙の質感の斜めの縞
    canvas.save();
    canvas.clipRRect(frame);
    final stripePaint = Paint()
      ..color = SnapmonColors.textOnBackground.withValues(alpha: .04)
      ..strokeWidth = 8;
    for (var offset = -236.0; offset < 236; offset += 16) {
      canvas.drawLine(
        Offset(offset - 118, 118),
        Offset(offset + 118, -118),
        stripePaint,
      );
    }
    canvas.restore();
    canvas.restore();
  }

  void _paintFinderCorners({required Canvas canvas, required Size size}) {
    final paint = Paint()
      ..color = SnapmonColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    const inset = 18.0;
    const top = 22.0;
    const length = 30.0;
    const radius = 8.0;
    for (final (sx, sy) in [
      (1.0, 1.0),
      (-1.0, 1.0),
      (1.0, -1.0),
      (-1.0, -1.0),
    ]) {
      canvas.save();
      canvas.translate(sx > 0 ? 0 : size.width, sy > 0 ? 0 : size.height);
      canvas.scale(sx, sy);
      canvas.drawPath(
        Path()
          ..moveTo(inset + 2, top + length)
          ..lineTo(inset + 2, top + 2 + radius)
          ..arcToPoint(
            const Offset(inset + 2 + radius, top + 2),
            radius: const Radius.circular(radius),
          )
          ..lineTo(inset + length, top + 2),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintAura({required Canvas canvas, required Offset center}) {
    // オーラ: 不透明度 .55〜.9、大きさ 1〜1.06 倍
    final radius = 115 * (1 + .06 * progress);
    final opacity = .55 + .35 * progress;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            SnapmonColors.accent.withValues(alpha: .35 * opacity),
            SnapmonColors.accent.withValues(alpha: 0),
          ],
          stops: const [0, .7],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  /// 170×170 の箱の左上を原点に、切り出されたマグカップと目・電気の飾りを描く。
  void _paintMonster({required Canvas canvas}) {
    final body = RRect.fromRectAndCorners(
      const Rect.fromLTWH(10, 30, 112, 120),
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: const Radius.circular(44),
      bottomRight: const Radius.circular(44),
    );
    // 切り出しの輪郭: 胴体の外側に地の色 (3px) と黄緑 (6px)。線は中心から両側に広がるため幅を 2 倍にして胴体で内側を隠す
    for (final (color, width) in [
      (SnapmonColors.accent, 18.0),
      (SnapmonColors.background, 6.0),
    ]) {
      canvas.drawRRect(
        body,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }
    canvas.drawRRect(body, Paint()..color = _mugColor);
    // 胴体の右下の陰
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRRect(
      body.shift(const Offset(16, 18)),
      Paint()..color = _mugShadeColor,
    );
    canvas.restore();
    // 取っ手 (右側の半円の輪。線の太さ 14、外側に地の色 3px)
    const handleRect = Rect.fromLTWH(119, 61, 38, 44);
    for (final (color, width) in [
      (SnapmonColors.background, 20.0),
      (_mugColor, 14.0),
    ]) {
      canvas.drawArc(
        handleRect,
        -math.pi / 2,
        math.pi,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }
    // 目
    for (final left in [36.0, 70.0]) {
      canvas.drawOval(
        Rect.fromLTWH(left, 66, 22, 26),
        Paint()..color = SnapmonColors.textOnBackground,
      );
      canvas.drawOval(
        Rect.fromLTWH(left + 10, 76, 9, 11),
        Paint()..color = SnapmonColors.background,
      );
    }
    // 電気の属性の飾り (モックの 24×28 の稲妻を 40×48 に)
    canvas.save();
    canvas.translate(118, -6);
    canvas.scale(40 / 24, 48 / 28);
    canvas.drawPath(
      Path()
        ..moveTo(13, 1)
        ..lineTo(3, 16)
        ..lineTo(11, 16)
        ..lineTo(9, 27)
        ..lineTo(21, 10)
        ..lineTo(13, 10)
        ..close(),
      Paint()..color = SnapmonColors.accent,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// タイトルのボタンを押した後、下タブ・生成に進める状態になるまで出す画面。年齢の確認の状態とログインの状態に応じて
/// 年齢の確認・使えない・ログイン (失敗なら「つながりませんでした」と再試行) の画面を出し、進める状態になったら閉じる。
class _SessionGateScreen extends StatefulWidget {
  const _SessionGateScreen({
    required this.ageConfirmationStore,
    required this.ageVerifiedSessionStore,
    required this.isDebugSkipEnabled,
  });

  final AgeConfirmationStore ageConfirmationStore;
  final AgeVerifiedSessionStore ageVerifiedSessionStore;
  final bool isDebugSkipEnabled;

  @override
  State<_SessionGateScreen> createState() => _SessionGateScreenState();
}

class _SessionGateScreenState extends State<_SessionGateScreen> {
  bool _hasPopped = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.ageConfirmationStore,
      widget.ageVerifiedSessionStore,
    ]),
    builder: (context, _) {
      if (widget.ageVerifiedSessionStore.canEnterApp) {
        if (!_hasPopped) {
          _hasPopped = true;
          // build の途中に閉じないため、このフレームの後に閉じる
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
        return const Scaffold(body: SizedBox.shrink());
      }
      return switch (widget.ageConfirmationStore.status) {
        AgeConfirmationStatus.unanswered => AgeGateScreen(
          ageConfirmationStore: widget.ageConfirmationStore,
        ),
        AgeConfirmationStatus.restricted => const AgeRestrictedScreen(),
        AgeConfirmationStatus.allowed => AgeVerifiedSessionScreen(
          ageConfirmationStore: widget.ageConfirmationStore,
          ageVerifiedSessionStore: widget.ageVerifiedSessionStore,
          isDebugSkipEnabled: widget.isDebugSkipEnabled,
        ),
      };
    },
  );
}
