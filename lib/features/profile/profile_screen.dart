import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/trainer_icon.dart';
import '../action_card/action_card_screen.dart';
import '../action_card/action_card_store.dart';
import '../dex/dex_store.dart';
import '../opponent/pvp_client.dart';

/// プロフィール画面。対戦の相手と対戦画面に出るアイコン (端末の写真から選ぶ) と表示名を変える。設定の「プロフィール」から開く。
/// 画面を開く前に読んだ [initialProfile] から始め、保存できた値は画面に残して [onProfileChanged] で開いた側へ渡す。
class ProfileScreen extends StatefulWidget {
  /// プロフィール画面を作る。
  const ProfileScreen({
    super.key,
    required this.initialProfile,
    required this.onProfileChanged,
    required this.pvpClient,
    required this.pickPhoto,
    required this.preparePhoto,
    required this.dexStore,
  });

  /// Action Card の画面が技の名前・属性を引く定義の持ち主。
  final DexStore dexStore;

  /// 開いた時の表示名とアイコン。
  final PlayerProfile initialProfile;

  /// 表示名かアイコンを保存できるたびに、保存後の表示名とアイコンを受け取る。
  final void Function({required PlayerProfile profile}) onProfileChanged;

  /// 表示名とアイコンの保存。
  final PvpClient pvpClient;

  /// 端末のアルバムから写真を 1 枚選んでもらう。選ばずに閉じた時は null ([MonsterGenerator.pickAlbumPhoto] と同じ)。
  final Future<Uint8List?> Function() pickPhoto;

  /// 選んだ写真を、送る形 (向きを直した長辺 1024px 以下の JPEG) にする ([MonsterGenerator.preparePhoto] と同じ)。
  final Future<Uint8List> Function({required Uint8List sourceBytes})
  preparePhoto;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// [ProfileScreen] の表示中の値と保存の状態。
class _ProfileScreenState extends State<ProfileScreen> {
  /// 画面に出している表示名。保存できた値で置き換える。
  late String _displayName = widget.initialProfile.displayName;

  /// 画面に出しているアイコンの Storage のパス。保存できた値で置き換える。
  late String? _iconPath = widget.initialProfile.iconPath;

  /// アイコンを選んでから保存し終えるまでの間か。間は選び直させない (先に送った写真の結果で上書きされるため)。
  bool _isUpdatingIcon = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // package をまだ読めていないと Action Card の入口が出ないため、開いた時とストアの値が変わるたびに足りなければ読み込む
    // (読めた後と読み込みの途中は何もしないため、何度呼んでも読み込みは重ならない)
    ActionCardScope.maybeOf(context)?.refreshPackagesIfMissing();
  }

  /// 画面の下に [message] を 1 つだけ出す (前の通知は消す)。
  void _showMessage({required String message}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// 保存できた [profile] を画面に出し、開いた側へ渡す。
  void _applySavedProfile({required PlayerProfile profile}) {
    setState(() {
      _displayName = profile.displayName;
      _iconPath = profile.iconPath;
    });
    widget.onProfileChanged(profile: profile);
  }

  /// 写真を選んでもらい、アイコンにする。検査で断られた時と失敗した時は、その理由をそのまま出す。
  Future<void> _changeIcon() async {
    setState(() => _isUpdatingIcon = true);
    try {
      final sourceBytes = await widget.pickPhoto();
      if (sourceBytes == null) {
        return;
      }
      final iconPath = await widget.pvpClient.updateIcon(
        photo: await widget.preparePhoto(sourceBytes: sourceBytes),
      );
      if (mounted) {
        _applySavedProfile(
          profile: (displayName: _displayName, iconPath: iconPath),
        );
        _showMessage(message: context.l10n.profileIconUpdated);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(message: error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingIcon = false);
      }
    }
  }

  /// 表示名を入力するダイアログを開き、保存できた名前を画面に出す。
  Future<void> _editDisplayName() async {
    final savedDisplayName = await showDialog<String>(
      context: context,
      // 保存の途中に外を押して閉じると、保存できた名前が画面に反映されないため、閉じるのは「やめる」だけにする
      barrierDismissible: false,
      builder: (context) => _DisplayNameDialog(
        initialDisplayName: _displayName,
        updateDisplayName: widget.pvpClient.updateDisplayName,
      ),
    );
    if (savedDisplayName != null && mounted) {
      _applySavedProfile(
        profile: (displayName: savedDisplayName, iconPath: _iconPath),
      );
    }
  }

  @override
  // アイコンを保存し終えるまでは戻らせない (閉じた後に保存が終わると、保存できたアイコンを開いた側へ渡せないため)
  Widget build(BuildContext context) => PopScope(
    canPop: !_isUpdatingIcon,
    child: Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsProfileSection)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            // 96: アイコンを変える画面で、選んだ写真の切り取った中身 (256px の PNG) を見て確かめられる大きさ
            child: TrainerIcon(
              key: const Key('profile-icon'),
              displayName: _displayName,
              iconPath: _iconPath,
              dimension: 96,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              key: const Key('profile-change-icon'),
              onPressed: _isUpdatingIcon ? null : _changeIcon,
              icon: _isUpdatingIcon
                  // 16: 読み込みの間に置き換わるアイコンの枠 (OutlinedButton.icon の既定の 18) に収める。
                  // strokeWidth 2: 既定の 4 は一辺 16 の輪には太く、輪の内側がほとんど残らないため
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined),
              label: Text(context.l10n.profileChangeIcon),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.profileIconHelper,
            textAlign: TextAlign.center,
            style: SnapmonTextStyles.small,
          ),
          const SizedBox(height: 24),
          ListTile(
            key: const Key('display-name'),
            leading: const Icon(Icons.badge_outlined),
            title: Text(context.l10n.settingsDisplayName),
            subtitle: Text(_displayName),
            trailing: const Icon(Icons.edit),
            onTap: _editDisplayName,
          ),
          if (ActionCardScope.maybeOf(context)?.isScreenEntryVisible ?? false)
            ListTile(
              key: const Key('action-card-entry-profile'),
              leading: const Icon(Icons.style_outlined),
              title: Text(context.l10n.actionCardTitle),
              subtitle: Text(context.l10n.actionCardEntrySubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      ActionCardScreen(dexStore: widget.dexStore),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 表示名を入力するダイアログ。保存できたら保存した名前で閉じ、できなければ理由をそのまま出して閉じない。
class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({
    required this.initialDisplayName,
    required this.updateDisplayName,
  });

  /// 入力欄の最初の値 (今の表示名)。
  final String initialDisplayName;

  /// 表示名を保存し、保存した名前を返す。使えない名前の時は理由を例外で投げる。
  final Future<String> Function({required String displayName})
  updateDisplayName;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

/// [_DisplayNameDialog] の入力と保存の状態。
class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  /// 表示名の入力欄の値。
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialDisplayName,
  );

  /// 保存を送ってから結果が返るまでの間か。
  bool _isSaving = false;

  /// 保存できなかった理由。無ければ null。
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 入力した名前を保存し、保存できたらその名前でダイアログを閉じる。
  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      final savedDisplayName = await widget.updateDisplayName(
        displayName: _controller.text,
      );
      if (mounted) {
        Navigator.of(context).pop(savedDisplayName);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = error.toString();
        });
      }
    }
  }

  @override
  // 保存の途中は戻る操作でも閉じさせない (保存できた名前を画面に反映できなくなるため)
  Widget build(BuildContext context) => PopScope(
    canPop: !_isSaving,
    child: AlertDialog(
      title: Text(context.l10n.settingsDisplayName),
      content: TextField(
        key: const Key('display-name-field'),
        controller: _controller,
        autofocus: true,
        enabled: !_isSaving,
        decoration: InputDecoration(
          helperText: context.l10n.settingsDisplayNameHelper,
          errorText: _errorText,
          errorMaxLines: 4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          key: const Key('display-name-save'),
          onPressed: _isSaving ? null : _save,
          child: Text(context.l10n.settingsDisplayNameSave),
        ),
      ],
    ),
  );
}
