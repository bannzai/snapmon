import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/trainer_icon.dart';
import '../opponent/pvp_client.dart';

/// プロフィール画面。対戦の相手と対戦画面に出るアイコン (端末の写真から選ぶ) と表示名を変える。設定の「プロフィール」から開く。
/// 画面を開く前に読んだ [initialProfile] から始め、変えた値は画面に残す (閉じた後は開いた側がサーバーから読み直す)。
class ProfileScreen extends StatefulWidget {
  /// プロフィール画面を作る。
  const ProfileScreen({
    super.key,
    required this.initialProfile,
    required this.pvpClient,
    required this.pickPhoto,
    required this.preparePhoto,
  });

  /// 開いた時の表示名とアイコン。
  final TrainerProfile initialProfile;

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

class _ProfileScreenState extends State<ProfileScreen> {
  late TrainerProfile _profile = widget.initialProfile;

  /// アイコンを選んでから保存し終えるまでの間か。間は選び直させない (先に送った写真の結果で上書きされるため)。
  bool _isUpdatingIcon = false;

  void _showMessage({required String message}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

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
        setState(
          () => _profile = (
            displayName: _profile.displayName,
            iconPath: iconPath,
          ),
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

  Future<void> _editDisplayName() async {
    final savedDisplayName = await showDialog<String>(
      context: context,
      // 保存の途中に外を押して閉じると、保存できた名前が画面に反映されないため、閉じるのは「やめる」だけにする
      barrierDismissible: false,
      builder: (context) => _DisplayNameDialog(
        initialDisplayName: _profile.displayName,
        updateDisplayName: widget.pvpClient.updateDisplayName,
      ),
    );
    if (savedDisplayName != null && mounted) {
      setState(
        () => _profile = (
          displayName: savedDisplayName,
          iconPath: _profile.iconPath,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.settingsProfileSection)),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Center(
          child: TrainerIcon(
            key: const Key('profile-icon'),
            profile: _profile,
            dimension: 96,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            key: const Key('profile-change-icon'),
            onPressed: _isUpdatingIcon ? null : _changeIcon,
            icon: _isUpdatingIcon
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
          subtitle: Text(_profile.displayName),
          trailing: const Icon(Icons.edit),
          onTap: _editDisplayName,
        ),
      ],
    ),
  );
}

/// 表示名を入力するダイアログ。保存できたら保存した名前で閉じ、できなければ理由をそのまま出して閉じない。
class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({
    required this.initialDisplayName,
    required this.updateDisplayName,
  });

  final String initialDisplayName;
  final Future<String> Function({required String displayName})
  updateDisplayName;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialDisplayName,
  );
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
