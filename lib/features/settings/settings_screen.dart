import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../common_ui/scene_route.dart';
import '../../audio/game_audio.dart';
import '../../l10n/l10n.dart';
import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../monster_ui/trainer_icon.dart';
import '../battle/battle_recorder.dart';
import '../capture/monster_generator.dart';
import '../capture/ticket_purchase_sheet.dart';
import '../developer_menu/developer_menu_screen.dart';
import '../dex/dex_store.dart';
import '../opponent/pvp_client.dart';
import '../profile/profile_screen.dart';
import '../session/session_store.dart';
import '../share/card_sharer.dart';
import 'account_store.dart';

/// [uri] を外部のアプリ (ブラウザ・メール) で開き、開けたかを返す。
typedef OpenURL = Future<bool> Function({required Uri uri});

/// お問い合わせの宛先 (docs/index.html のサポートの連絡先と同じ)。
final Uri contactUri = Uri.parse('mailto:bannzai.app@gmail.com');

/// 紹介ページ (docs/index.html を GitHub Pages で公開したページ)。共有するカード画像と文章に入れる。
final Uri landingPageUri = Uri.parse('https://bannzai.github.io/snapmon/');

/// 利用規約 (docs/Terms.md を GitHub Pages で公開したページ)。
final Uri termsUri = Uri.parse('https://bannzai.github.io/snapmon/Terms');

/// プライバシーポリシー (docs/PrivacyPolicy.md を GitHub Pages で公開したページ)。
final Uri privacyPolicyUri = Uri.parse(
  'https://bannzai.github.io/snapmon/PrivacyPolicy',
);

/// アカウントの削除の手順 (docs/AccountDeletion.md を GitHub Pages で公開したページ)。
final Uri accountDeletionUri = Uri.parse(
  'https://bannzai.github.io/snapmon/AccountDeletion',
);

/// 設定画面。図鑑・撮る・対戦の各画面の右上の歯車から開く (モックに設定画面は無いため置き場所は agent が決めた)。
class SettingsScreen extends StatelessWidget {
  /// 設定画面を作る。
  const SettingsScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.sessionStore,
    required this.monsterGenerator,
    required this.pvpClient,
    required this.cardSharer,
    required this.openURL,
    required this.isDeveloperMenuEnabled,
    required this.accountStore,
    required this.battleRecorder,
  });

  /// バトルの記録と計測 (開発者メニューの見本の写真から始めた初回のバトルが使う)。
  final BattleRecorder battleRecorder;

  /// プロフィールの読み込みと変更 (開発者メニューの見本の写真から始めた初回のバトルの相手の取得にも使う)。
  final PvpClient pvpClient;

  /// 見本データ (開発者メニューが使う)。
  final SampleData sampleData;

  /// 図鑑と手持ち (開発者メニューと、連携済みのアカウントへの切り替えの確認で消える数の表示が使う)。
  final DexStore dexStore;

  /// ログイン (開発者メニューが使う)。
  final SessionStore sessionStore;

  /// 生成の呼び出しと計測 (開発者メニューと、プロフィール画面のアイコンの写真を選ぶのに使う)。
  final MonsterGenerator monsterGenerator;

  /// 図鑑のカードの共有に使う関数の組 (開発者メニューが使う)。
  final CardSharer cardSharer;

  /// リンクを開く。
  final OpenURL openURL;

  /// 開発者メニューの入口を出すか。release ビルドでは [kDebugMode] が const の false のため、
  /// この値に関係なく入口と開発者メニューのコードがビルドから除かれる。widget test は false を渡して出ないことを確かめる。
  final bool isDeveloperMenuEnabled;

  /// アカウントの連携 (データを引き継ぐ) と削除。
  final AccountStore accountStore;

  void _showMessage({required BuildContext context, required String message}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  /// 「データを引き継ぐ」。いまの匿名アカウントに連携し、別の端末で連携済みなら切り替えてよいかを確かめてから切り替える。
  Future<void> _link({required BuildContext context}) async {
    final Future<String> Function()? signInToLinkedAccount;
    try {
      signInToLinkedAccount = await accountStore.link();
    } catch (error) {
      if (context.mounted) {
        _showMessage(context: context, message: error.toString());
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (signInToLinkedAccount == null) {
      _showMessage(
        context: context,
        message: context.l10n.settingsLinked(accountStore.linkProviderName),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsSwitchAccountTitle),
        content: Text(
          context.l10n.settingsSwitchAccountMessage(
            accountStore.linkProviderName,
            dexStore.monsters.length,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.settingsSwitchAccountConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await accountStore.switchToLinkedAccount(
        signInToLinkedAccount: signInToLinkedAccount,
      );
    } catch (error) {
      if (context.mounted) {
        _showMessage(context: context, message: error.toString());
      }
      return;
    }
    if (context.mounted) {
      _showMessage(
        context: context,
        message: context.l10n.settingsSwitchedAccount,
      );
    }
  }

  /// 「アカウントを削除」。確かめてから消し、消せたらタイトル画面 (アプリのルート) に戻す。
  Future<void> _delete({required BuildContext context}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsDeleteAccountTitle),
        content: Text(context.l10n.settingsDeleteAccountMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.settingsDeleteAccountConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await accountStore.delete();
    } catch (error) {
      if (context.mounted) {
        _showMessage(context: context, message: error.toString());
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// [uri] を開き、開けなかった時 (メールのアプリが無い simulator など) はそのことを伝える。
  /// 開くアプリが無い Android では false ではなく例外になるため、例外の時はその内容を出す。
  Future<void> _open({required BuildContext context, required Uri uri}) async {
    final message = await _openAndDescribeFailure(
      uri: uri,
      couldNotOpenMessage: context.l10n.commonCouldNotOpenURL(uri.toString()),
    );
    if (message == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// [uri] を開く。開けた時は null、開けなかった時は利用者に出す文言 (false が返った時は [couldNotOpenMessage]) を返す。
  Future<String?> _openAndDescribeFailure({
    required Uri uri,
    required String couldNotOpenMessage,
  }) async {
    try {
      return await openURL(uri: uri) ? null : couldNotOpenMessage;
    } on Exception catch (error) {
      return error.toString();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.settingsTitle)),
    body: ListView(
      children: [
        // 「データを引き継ぐ」で別のアカウントに切り替わると uid が変わるため、uid ごとに作り直して表示名を読み直す
        // (前の uid のプロフィールを出したまま保存させないため)
        ListenableBuilder(
          listenable: Listenable.merge([
            accountStore,
            accountStore.sessionStore,
          ]),
          builder: (context, _) => _ProfileTile(
            key: ValueKey(accountStore.sessionStore.uid),
            isAccountWorking: accountStore.isWorking,
            pvpClient: pvpClient,
            monsterGenerator: monsterGenerator,
            dexStore: dexStore,
          ),
        ),
        _SectionTitle(title: context.l10n.settingsSoundSection),
        _SoundSwitches(gameAudio: GameAudioScope.of(context)),
        _SectionTitle(title: context.l10n.settingsSupportSection),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(context.l10n.commonContact),
          onTap: () => _open(context: context, uri: contactUri),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(context.l10n.settingsTerms),
          onTap: () => _open(context: context, uri: termsUri),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(context.l10n.settingsPrivacyPolicy),
          onTap: () => _open(context: context, uri: privacyPolicyUri),
        ),
        TicketPurchaseSyncTile(monsterGenerator: monsterGenerator),
        _SectionTitle(title: context.l10n.settingsAccountSection),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(context.l10n.settingsAboutAccountDeletion),
          onTap: () => _open(context: context, uri: accountDeletionUri),
        ),
        // DEBUG でログインを飛ばした時は、連携・削除するアカウントが無いため押せなくする
        ListenableBuilder(
          listenable: Listenable.merge([
            accountStore,
            accountStore.sessionStore,
          ]),
          builder: (context, _) {
            final linkedProviderNames = accountStore.linkedProviderNames;
            final canOperate =
                accountStore.isSignedIn && !accountStore.isWorking;
            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: Text(context.l10n.settingsTransferData),
                  subtitle: Text(
                    linkedProviderNames.isEmpty
                        ? context.l10n.settingsTransferDataDescription(
                            accountStore.linkProviderName,
                          )
                        : context.l10n.settingsLinkedWith(
                            linkedProviderNames.join(
                              context.l10n.settingsProviderSeparator,
                            ),
                          ),
                  ),
                  enabled: canOperate && linkedProviderNames.isEmpty,
                  onTap: () => _link(context: context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(context.l10n.settingsDeleteAccount),
                  enabled: canOperate,
                  onTap: () => _delete(context: context),
                ),
              ],
            );
          },
        ),
        if (kDebugMode && isDeveloperMenuEnabled) ...[
          const _SectionTitle(title: '開発'),
          ListTile(
            leading: const Icon(Icons.build_outlined),
            title: const Text('開発者メニュー'),
            onTap: () => Navigator.of(context).push(
              sceneRoute<void>(
                builder: (context) => DeveloperMenuScreen(
                  sampleData: sampleData,
                  dexStore: dexStore,
                  sessionStore: sessionStore,
                  monsterGenerator: monsterGenerator,
                  cardSharer: cardSharer,
                  pvpClient: pvpClient,
                  battleRecorder: battleRecorder,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// 「BGM」「効果音」のスイッチ。切り替えはその場で音に反映され、端末に保存される。
class _SoundSwitches extends StatelessWidget {
  const _SoundSwitches({required this.gameAudio});

  /// BGM・効果音のオン・オフ。
  final GameAudio gameAudio;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        key: const Key('settings-background-music'),
        secondary: const Icon(Icons.music_note_outlined),
        title: Text(context.l10n.settingsBackgroundMusic),
        value: gameAudio.isBackgroundMusicEnabled,
        onChanged: (enabled) =>
            gameAudio.setBackgroundMusicEnabled(enabled: enabled),
      ),
      SwitchListTile(
        key: const Key('settings-sound-effects'),
        secondary: const Icon(Icons.volume_up_outlined),
        title: Text(context.l10n.settingsSoundEffects),
        value: gameAudio.isSoundEffectsEnabled,
        onChanged: (enabled) =>
            gameAudio.setSoundEffectsEnabled(enabled: enabled),
      ),
    ],
  );
}

/// プロフィールの節。表示名とアイコンはサーバー (Functions の getDisplayName) が返した値を出し、押すとプロフィール画面を開く。
/// プロフィール画面で保存できた値はその場で出し、閉じたら読み直す (読み直しに失敗しても保存できた値を出し続けるため、エラーは出さない)。ログインが無い時 (DEBUG ビルドでログインを飛ばした時) は値が無いため節を出さない。
class _ProfileTile extends StatefulWidget {
  const _ProfileTile({
    required super.key,
    required this.isAccountWorking,
    required this.pvpClient,
    required this.monsterGenerator,
    required this.dexStore,
  });

  /// プロフィール画面から開く Action Card の画面が技の名前・属性を引く定義の持ち主。
  final DexStore dexStore;

  /// アカウントの連携・切り替え・削除の途中か。途中は押せなくする (切り替わった後も前の uid の値を持つプロフィール画面を開かせないため)。
  final bool isAccountWorking;

  /// プロフィールの読み込みと保存。
  final PvpClient pvpClient;

  /// プロフィール画面がアイコンの写真を選んで送る形にするのに使う。
  final MonsterGenerator monsterGenerator;

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

/// [_ProfileTile] の読み込みの状態。
class _ProfileTileState extends State<_ProfileTile> {
  /// 今の表示名とアイコン。読み込み中・ログインが無い時は null。
  PlayerProfile? _profile;

  /// 読み込みの失敗。
  Object? _loadError;

  /// 最初の読み込みが終わる前か。
  bool _isLoading = true;

  /// 読み込みを始めるか保存できた値を受け取るたびに増える番号。読み込みの結果は、始めた時の番号のままの時だけ反映する (遅れて返った古い読み込みで、保存できた値や新しい読み込みの結果を戻さないため)。
  int _profileRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 自分のプロフィールを読み、読めた値か失敗を画面に出す。結果が返るまでに新しい読み込みか保存があった時は何も変えない。
  Future<void> _load() async {
    final loadRevision = ++_profileRevision;
    try {
      final profile = await widget.pvpClient.fetchProfile();
      if (mounted && loadRevision == _profileRevision) {
        setState(() {
          _profile = profile;
          _loadError = null;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted && loadRevision == _profileRevision) {
        setState(() {
          _loadError = error;
          _isLoading = false;
        });
      }
    }
  }

  /// プロフィール画面で保存できた [profile] を項目に出す。
  void _applySavedProfile({required PlayerProfile profile}) {
    _profileRevision++;
    setState(() => _profile = profile);
  }

  /// [profile] から始めるプロフィール画面を開き、閉じたら読み直す。保存できた値は読み直しを待たずに出す。
  Future<void> _open({required PlayerProfile profile}) async {
    await Navigator.of(context).push(
      sceneRoute<void>(
        builder: (context) => ProfileScreen(
          initialProfile: profile,
          onProfileChanged: _applySavedProfile,
          pvpClient: widget.pvpClient,
          pickPhoto: widget.monsterGenerator.pickAlbumPhoto,
          preparePhoto: widget.monsterGenerator.preparePhoto,
          dexStore: widget.dexStore,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (!_isLoading && profile == null && _loadError == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title: context.l10n.settingsProfileSection),
        ListTile(
          key: const Key('profile'),
          enabled: !widget.isAccountWorking,
          leading: profile == null
              ? const Icon(Icons.badge_outlined)
              // 32: ListTile の leading に置く他の項目のアイコン (24) の枠に近い大きさで、アイコンの写真を見分けられるため
              : TrainerIcon(
                  displayName: profile.displayName,
                  iconPath: profile.iconPath,
                  dimension: 32,
                ),
          title: Text(context.l10n.settingsProfileSection),
          subtitle: Text(
            profile?.displayName ??
                _loadError?.toString() ??
                context.l10n.settingsDisplayNameLoading,
          ),
          trailing: profile == null ? null : const Icon(Icons.chevron_right),
          onTap: profile == null
              ? (_loadError == null ? null : _load)
              : () => _open(profile: profile),
        ),
      ],
    );
  }
}

/// 設定の節の見出し。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Text(title, style: SnapmonTextStyles.caption),
  );
}
