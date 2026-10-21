import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/master/master_data.dart';

/// アプリに同梱した master の asset のパス。
const String masterDataAssetPath = 'assets/master/master.json';

/// [assetBundle] から同梱の master を読む。アプリからは `rootBundle` を渡す。
Future<MasterData> loadMasterData({required AssetBundle assetBundle}) async =>
    MasterData.fromJson(
      json:
          jsonDecode(await assetBundle.loadString(masterDataAssetPath))
              as Map<String, dynamic>,
    );
