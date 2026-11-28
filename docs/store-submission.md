# Microsoft Store 提出手順

最終更新: 2026-11-28
対象 Issue: #35（関連 #39 / #58）

このドキュメントは、**提出ボタンを押すまでに何をどこへ入れるか**をまとめたものです。
掲載文の確定稿は [store-listing.md](store-listing.md)、MSIX の実測は
[msix-verification.md](msix-verification.md) にあります。

## 0. 前提（予約済みの値）

| 項目 | 値 |
| --- | --- |
| 製品名 | Game Audio Manager |
| Store ID | 9MSZ7691JXVM |
| Package Identity Name | `tonbiattack.GameAudioManager` |
| Publisher | `CN=2F14A66E-02DF-43E2-93E0-5C5900B38D2E` |
| Package Family Name | `tonbiattack.GameAudioManager_e28ksxe3fc9w4` |
| 初回提出期限 | 予約から約3か月（2027年2月下旬） |

これらは `packaging/Package/AppxManifest.xml` に入っており、
`tests/msix-manifest.tests.ps1` が一致を検査します。**Partner Center の画面と食い違ったら
このテストが落ちる**ので、値の変更はテストとセットで行ってください。

## 0.5 配布アーキテクチャ

**x64 のみ**を公開します。ARM64 端末では x64 エミュレーションで動作します。
ARM64 ネイティブが必要になった場合は、`publish.ps1 -Runtime win-arm64` と
マニフェストの `ProcessorArchitecture` を分けたパッケージを追加し、バンドルで提出します
（今回の初回提出では行いません）。

## 1. 提出するパッケージを用意する

**ストア提出用の MSIX は署名不要**です（Microsoft が取り込み時に再署名します）。
配布用の OV/EV 証明書は購入していませんし、必要ありません。

### CI から取得する（推奨）

タグを push すると `release` ワークフローが
`game-audio-manager-<version>-win-x64.msix` を作り、**`store-msix` アーティファクト**として
アップロードします。Actions の実行ページからダウンロードしてください。

```powershell
gh run list --workflow release --limit 1
gh run download <run-id> -n store-msix
```

### ローカルで作る

```powershell
./scripts/publish.ps1 -Version 2.0.0
./scripts/pack-msix.ps1 -Version 2.0.0.0
# artifacts\GameAudioManager.msix
```

- バージョンは**4要素**（`2.0.0.0`）。ストアは公開済みバージョンより大きい値だけを受け付けます
- マニフェストの `Identity` は予約値のまま（`pack-msix.ps1` の既定 Publisher も同じ）
- 生成物は**未署名**で構いません。サイドロード検証をしたい場合だけ
  `scripts/make-test-msix.ps1` で自己署名し、管理者権限で証明書を信頼してください

### アップロード形式

公式には `.msixupload`（シンボル付き）が推奨ですが、**`.msix` も受理されます**
（[Upload MSIX app packages](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/upload-app-packages)）。
本プロジェクトは `.msix` をそのままアップロードします。クラッシュ解析用のシンボルは含みません。

## 2. Partner Center の入力

| セクション | 入れるもの | 出典 |
| --- | --- | --- |
| Product name | 予約済み（`Game Audio Manager`） | — |
| Properties | カテゴリ「ユーティリティ」、著作権 `© 2026 tonbiattack`、プライバシー URL、サポート URL | [store-listing.md](store-listing.md) |
| Age rating | IARC の質問票（暴力・課金・位置情報などはすべて「なし」） | 画面の質問に回答 |
| Packages | 手順1の `.msix` | — |
| Store listing | 説明文・短い説明・キーワード・スクリーンショット4枚・300×300 アイコン | [store-listing.md](store-listing.md) |
| Submission options | `runFullTrust` の使用理由（下記） | 本ドキュメント |
| Notes for certification | 審査担当者向けの説明（下記） | 本ドキュメント |

スクリーンショットは `docs/images/store/` にあります（1920×1080、日本語/英語 × ライト/ダーク）。
撮り直すときは:

```powershell
./scripts/publish.ps1 -Version 2.0.0
./scripts/capture-store-screenshots.ps1    # 設定は自動でバックアップ・復元されます
```

## 3. 貼り付け用の文面

### Submission options — `runFullTrust` の理由

> The app is a WPF (Win32) desktop application packaged with MSIX. It needs the full-trust
> capability to enumerate audio endpoints and audio sessions through the Windows Core Audio
> APIs (IMMDeviceEnumerator / IAudioSessionManager2) and to set the per-app default playback
> device on the user's behalf. It does not install drivers, services, or shell extensions.
> No file types or protocols are registered. No network access is performed.

### Notes for certification（審査担当者向け）

```
No test account is required. The app has no sign-in and makes no network requests.

How to test:
1. Install and launch the app. It opens a window and also adds a tray icon.
2. The list shows audio-capable apps that are currently running.
3. Start audio playback in any app (for example a browser playing a video).
4. Select the row of that app, choose an output device in the bottom dropdown, and press
   the Apply button ("適用" in Japanese).
5. A status message confirms the choice was recorded. Windows applies it when the app
   creates its next audio session, so restart playback in the target app to hear the change.
6. The reset button ("Windows の既定へ戻す") restores the Windows default device.
7. The mute button ("ミュートする") mutes or unmutes the selected app.
8. "ログオン時に自動起動" (start with Windows) registers a startup task. Windows shows it in
   Settings > Apps > Startup, where it can be disabled by the user.

Implementation notes:
- Per-app output routing uses the Windows audio policy API
  (activation class "Windows.Media.Internal.AudioPolicyConfig"), the same mechanism used by
  other Store apps such as EarTrumpet. It is called only in response to an explicit user
  action in the UI; nothing is changed in the background without a configured rule that the
  user created.
- Settings are stored under the package's LocalState. The app does not write to HKCU\Run.
- The app requests only the runFullTrust restricted capability.
```

> 非公開 API を使っていることは**隠さず**書きます。ポリシー 10.2.8 は
> 「unsupported ways での未文書化 API の使用」を禁じており、判断は個別です
> （[msix-verification.md](msix-verification.md) の「Store ポリシー」）。
> 前例（EarTrumpet）を添える場合は Store の URL も一緒に書いてください。

## 4. 提出前チェックリスト

- [ ] `dotnet test GameAudioManager.slnx -c Release` が成功する
- [ ] `tests/run-all.tests.ps1` が成功する（`msix-manifest.tests.ps1` を含む）
- [ ] `pack-msix.ps1` でパッケージが生成できる
- [ ] パッケージのバージョンが 4 要素で、公開済みより大きい
- [ ] スクリーンショットが 4 枚（1920×1080）そろっている
- [ ] 300×300 のアイコンがある（`docs/images/store/store-icon-300.png`）
- [ ] プライバシー URL が公開されている（`PRIVACY.md`）
- [ ] `runFullTrust` の理由と Notes for certification を貼った
- [ ] 管理者権限で署名済み MSIX をインストールし、起動・音声制御・アンインストールを確認した
- [ ] WACK を実行し、レポートを保存した（`appcert.exe`）

### 署名済み MSIX と WACK（管理者権限）

```powershell
# 管理者 PowerShell
./scripts/make-test-msix.ps1 -CreateDevCertificate
Export-Certificate -Cert Cert:\CurrentUser\My\<thumbprint> -FilePath $env:TEMP\gam-dev.cer
Import-Certificate -FilePath $env:TEMP\gam-dev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople

# 通常の PowerShell
Add-AppxPackage -Path .\artifacts\GameAudioManager.msix
Get-AppxPackage tonbiattack.GameAudioManager | Remove-AppxPackage

# 管理者 PowerShell で WACK
& 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe' reset
& 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\appcert.exe' test `
    -packagepath .\artifacts\GameAudioManager.msix -reportoutputpath .\artifacts\wack-report.xml
```

## 5. 提出後の運用

- **更新**は新しいバージョンの `.msix` をアップロードするだけ。Store が更新を配信します
- バージョンは 4 要素で、**公開済みより大きく**してください（例: `2.0.1.0`）
- 設定はパッケージの `LocalState` に残るため、更新で失われません
- 段階配信（パッケージ フライト）を使う場合は、同じ `Identity` のままバージョンだけ上げます
- 公開後にスポット チェック（追加の審査）が入る場合があります

## 6. 所有者しかできない作業

| 作業 | 理由 |
| --- | --- |
| Partner Center へのサインインと提出 | アカウント認証が必要 |
| 年齢レーティング（IARC）の回答 | 法的な表明 |
| 価格・市場の設定 | 販売方針 |
| 署名済み MSIX のインストール確認と WACK | 管理者権限が必要 |
| クリーンな Windows（VM 等）でのインストール・起動・アンインストール確認 | 環境の用意が必要 |
| 実際の公開（Publish） | 所有者の承認 |

## 7. 未解決のリスク（提出しても通過を保証しない）

- **非公開 API**（`Windows.Media.Internal.AudioPolicyConfig`）の利用が
  ポリシー 10.2.8 の「unsupported ways」に当たると判断される可能性
- `runFullTrust` は restricted capability のため、追加審査の対象
- `.msixupload`（シンボル付き）ではなく `.msix` で提出するため、クラッシュ解析は得られない
- ストアの要件・料金・審査基準は変わる。**申請直前に公式ドキュメントで再確認する**
