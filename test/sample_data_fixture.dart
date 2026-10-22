import 'dart:convert';
import 'dart:io';

import 'package:snapmon/sample/sample_data.dart';

/// テストが使う見本データ。アプリと同じファイル (`assets/samples/sample_monsters.json`) をリポジトリから読む。
SampleData loadSampleDataFixture() => SampleData.fromJson(
  json:
      jsonDecode(File(sampleDataAssetPath).readAsStringSync())
          as Map<String, dynamic>,
);
