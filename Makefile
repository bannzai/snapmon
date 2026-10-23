# ios target が flutter run する simulator。sim-boot でプロジェクト固有 simulator を起動して解決する (?= なので ios 以外の target では起動しない)
SIMULATOR_UDID ?= $(shell SCRIPT_QUIET=1 sim-boot | sed -n 's/^DEVICE_UDID=//p' | tail -n 1)

# 引数なしの make で ios を実行する (人が手で動作確認するための入口。検査・テストは CI が行う)
.DEFAULT_GOAL := ios

# プロジェクト固有の simulator (sim-boot で起動) へ flutter run する。SIMULATOR_UDID=<UDID> で対象を指定できる
.PHONY: ios
ios:
	@set -e; \
	simulator_udid="$(SIMULATOR_UDID)"; \
	[ -n "$$simulator_udid" ] || { echo "Error: sim-boot で Simulator を解決できません (sim-boot が PATH にあるか確認するか、SIMULATOR_UDID=<UDID> を指定してください)" >&2; exit 1; }; \
	flutter run --debug -d "$$simulator_udid"

# USB か Wi-Fi で繋いだ iPhone / iPad の実機へ flutter run する (署名は Runner.xcodeproj の Automatic + DEVELOPMENT_TEAM)。
# DEVICE=<デバイス ID> で対象を指定でき、未指定なら flutter devices から実機 (iOS で emulator でなく、この環境で使える isSupported のもの) を自動解決する。
# テストは scripts/test/test-makefile-targets.sh (flutter を差し替えて選択・失敗・引数を確かめる)
.PHONY: ios-device
ios-device:
	@device="$(DEVICE)"; \
	if [ -z "$$device" ]; then \
		device=$$(flutter devices --machine | jq -r '[.[] | select((.targetPlatform | startswith("ios")) and .emulator == false and .isSupported == true)][0].id // empty'); \
	fi; \
	[ -n "$$device" ] || { echo "Error: 繋がっている iOS の実機が見つかりません (Xcode で信頼済みか確認するか、DEVICE=<デバイス ID> を指定してください)" >&2; exit 1; }; \
	flutter run --debug -d "$$device"

# Web 版を手元の Chrome で起動する (flutter run が開発サーバーを立てて Chrome を開く。r でホットリロード、q で終了)。
# flutter config の enable-web が false の環境でも動くよう、先に有効にする (設定は ~/.flutter に残る)
.PHONY: web
web:
	flutter config --enable-web >/dev/null
	flutter run --debug -d chrome

# 起動中の Android Emulator へ flutter run する。DEVICE=<デバイス ID> で対象を指定でき、未指定なら flutter devices から emulator を自動解決する
.PHONY: android
android:
	@device="$(DEVICE)"; \
	if [ -z "$$device" ]; then \
		device=$$(flutter devices --machine | jq -r '[.[] | select((.targetPlatform | startswith("android")) and .emulator == true)][0].id // empty'); \
	fi; \
	[ -n "$$device" ] || { echo "Error: 起動中の Android Emulator が見つかりません (DEVICE=<デバイス ID> で指定してください)" >&2; exit 1; }; \
	flutter run --debug -d "$$device"

# Web 版のビルドだけを行う (成果物は build/web)。flutter config の enable-web が false の環境では失敗する
.PHONY: build-web
build-web:
	flutter build web --release

# CI (.github/workflows/flutter-ci.yml) の lint・test と同じ検査をまとめて実行する
.PHONY: verify
verify:
	flutter pub get
	flutter analyze --no-pub --no-fatal-infos --fatal-warnings
	dart format --set-exit-if-changed lib test
	flutter test
	bash scripts/test/test-set-webtunnel-setup-env-secret.sh
	bash scripts/test/test-makefile-targets.sh

.PHONY: clean
clean:
	flutter clean
