import 'dart:convert';

/// 32 bit に収めるためのマスク。Dart の VM (64 bit 整数) と Web (JavaScript の数値) で
/// 同じ値を得るため、ハッシュと擬似乱数の途中の値は毎回この範囲に切り詰める。
const int _uint32Mask = 0xFFFFFFFF;

/// [text] の UTF-8 のバイト列から FNV-1a (32 bit) のハッシュを返す。
/// `String.hashCode` は実行環境によって値が変わり得るため、保存した説明文から
/// 個体値の seed を作る用途ではこちらを使う。
int fnv1a32({required String text}) {
  // FNV-1a 32 bit の offset basis (http://www.isthe.com/chongo/tech/comp/fnv/ の定数)
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    // FNV prime 16777619 = 2^24 + 403。そのまま掛けると Web で 2^53 を超えて
    // 精度が落ちるため、シフトと小さい掛け算に分けて下位 32 bit だけを残す。
    hash = (((hash << 24) & _uint32Mask) + hash * 403) & _uint32Mask;
  }
  return hash;
}

/// seed から決定的に整数を引く擬似乱数 (xorshift32)。
/// `dart:math` の `Random(seed)` は実行環境をまたいだ同一性が保証されないため、
/// 同じ seed から VM・Web で同じ列を得る必要がある計算はこれを使う。
class DeterministicRandom {
  /// [seed] から擬似乱数を作る。xorshift32 は状態 0 から抜け出せないため、0 は別の値に置き換える。
  DeterministicRandom({required int seed})
    : state = (seed & _uint32Mask) == 0
          // 状態 0 の代わりの値。0 以外なら何でもよく、FNV-1a の offset basis を流用した
          ? 0x811C9DC5
          : seed & _uint32Mask;

  /// 現在の内部状態。バトルの状態に保存して続きから引き直すために公開する。
  int state;

  /// 次の 32 bit の値 (0 以上 2^32 未満) を返し、内部状態を進める。
  int nextUint32() {
    var value = state;
    value ^= (value << 13) & _uint32Mask;
    value ^= value >> 17;
    value ^= (value << 5) & _uint32Mask;
    state = value & _uint32Mask;
    return state;
  }

  /// [minimum] 以上 [maximum] 以下の整数を返す。
  int nextIntInRange({required int minimum, required int maximum}) {
    if (maximum < minimum) {
      throw ArgumentError('maximum ($maximum) が minimum ($minimum) より小さい');
    }
    return minimum + nextUint32() % (maximum - minimum + 1);
  }
}
