# ストア公開の準備

最終更新: 2026-11-28

対象 Issue: #35, #39, #58

提出の手順は [store-submission.md](store-submission.md) を参照してください。

## 1. 現在の状態

MSIX の実測結果と配布方式の決定は [docs/msix-verification.md](msix-verification.md) にまとめています。
要点だけ再掲します。

| 項目 | 状態 |
| --- | --- |
| 自己完結 EXE（GitHub Releases） | ✅ 生成できる（`scripts/publish.ps1`） |
| リリース CI（タグ → ZIP → Release） | ✅ `.github/workflows/release.yml` |
| MSIX パッケージ生成 | ✅ `scripts/pack-msix.ps1` |
| MSIX への署名（自己署名） | ✅ `scripts/make-test-msix.ps1 -CreateDevCertificate` |
| MSIX の登録・起動（開発者モード） | ✅ 実測済み（ルーズ登録。署名検証は伴わない） |
| MSIX 内からの音声ルーティング実測 | ✅ **成功**（パッケージ内から設定でき、パッケージ外の設定ストアに残り、実際のセッションに反映された） |
| MSIX の更新・アンインストール | ✅ 実測済み（設定は保持され、実行中プロセスも終了した） |
| 設定の保存先 | ✅ パッケージの `LocalState` に統一。EXE 版から初回に取り込み（ハッシュ一致を実測） |
| EXE 版との共存 | ✅ ミューテックスを分離し、同時起動できることを実測 |
| トレイ常駐・単一インスタンス | ✅ 実測済み（チャネルごとにミューテックスを分離） |
| ログオン時の自動起動 | ✅ `uap5:StartupTask` へ移行して実測（有効化で `State=2`、再起動後も維持。Windows 側で無効化された場合はメッセージ表示） |
| 署名済み MSIX のインストール | ❌ 未実施（証明書の信頼に管理者権限が必要） |
| Windows App Certification Kit | ❌ 未実施（`appcert.exe` が管理者権限を要求） |
| ストア掲載素材 | 🟡 下書きあり（本ドキュメント） |
| プライバシーポリシー | 🟡 下書きあり（本ドキュメント。10.5.1 により Desktop Bridge 製品は必須） |

## 2. インストール検証の手順（所有者が実行）

証明書の登録は**所有者の承認なしに行いません**。次のコマンドを手動で実行してください。

```powershell
# 0. パッケージと署名済み MSIX を作る（管理者不要・証明書は CurrentUser\My のみ）
./scripts/make-test-msix.ps1 -CreateDevCertificate
# 末尾に表示される thumbprint を控える
```

```powershell
# 1. 公開証明書を書き出す（管理者不要）
Export-Certificate -Cert Cert:\CurrentUser\My\<thumbprint> -FilePath $env:TEMP\gam-dev.cer

# 2. 端末の信頼ストアへ入れる（管理者 PowerShell で実行）
#    自己署名のルートは信頼されていないと 0x800B0109 でインストールが拒否される
Import-Certificate -FilePath $env:TEMP\gam-dev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople

# 3. インストール（管理者不要）
Add-AppxPackage -Path .\artifacts\GameAudioManager.msix
```

```powershell
# 4. 検証（この結果を #39 に記録する）
#    a) 起動する
Get-AppxPackage tonbiattack.GameAudioManager | Select-Object PackageFullName
Start-Process shell:AppsFolder\tonbiattack.GameAudioManager_e28ksxe3fc9w4!GameAudioManager

#    b) アプリから出力先を変更し、レジストリに書かれたか確認
Get-ChildItem 'HKCU:\Software\Microsoft\Multimedia\Audio\DefaultEndpoint' |
  ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    if ($p.'(default)' -like '*<対象exe>*') { "$($_.PSChildName)"; $p }
  }

#    c) 対象アプリを再起動し、実際に新しいデバイスから音が出るか確認
#    d) ミュート、トレイ常駐、ログオン時自動起動も確認
```

```powershell
# 5. 後片付け
Get-AppxPackage tonbiattack.GameAudioManager | Remove-AppxPackage
Get-ChildItem Cert:\LocalMachine\TrustedPeople |
  Where-Object { $_.Subject -eq 'CN=GameAudioManager-Dev' } | Remove-Item   # 管理者
./scripts/make-test-msix.ps1 -RemoveDevCertificate -CertificateThumbprint <thumbprint>
```

### 開発者モードでの登録（管理者不要・署名不要）

署名と信頼登録を省きたい場合は、ルーズ登録で**パッケージ ID を持つ実行**を再現できます
（本ドキュメントの実測はこの方法）。署名検証は行われないため、配布経路の検証にはなりません。

```powershell
$makeappx = (Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'makeappx.exe' |
  Where-Object FullName -match '\\x64\\' | Sort-Object FullName -Descending | Select-Object -First 1).FullName
& $makeappx unpack /p .\artifacts\GameAudioManager.msix /d .\artifacts\app-package /o
Add-AppxPackage -Register .\artifacts\app-package\AppxManifest.xml
$pkg = Get-AppxPackage tonbiattack.GameAudioManager
Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($pkg.PackageFamilyName)!GameAudioManager"
Get-AppxPackage tonbiattack.GameAudioManager | Remove-AppxPackage
```

### 検証したい観点（実測済みの結果）

- MSIX 内から `Windows.Media.Internal.AudioPolicyConfig` を呼べるか → ✅ 呼べる
- パッケージの設定がパッケージ外から見えるか → ✅ 見える（`HKCU\...\DefaultEndpoint` に書かれる）
- 実際の音声セッションに反映されるか → ✅ 反映される（対象アプリのセッションを作り直すと指定デバイスに載る）
- 自動起動・設定の保存先・既存 EXE 版との共存 → ✅ #58 で対応・再実測（[docs/msix-verification.md](msix-verification.md)）

## 3. 配布方式の決定

**GitHub Releases の自己完結 EXE を維持し、Store へ出す場合は MSIX 方式を採る（EXE/MSI 方式は採らない）。**

| 観点 | MSIX（Store） | EXE / MSI（Store の Win32 提出） |
| --- | --- | --- |
| 署名費用 | **ストアが再署名（$0）** | OV 証明書 約 $150–300/年など（提出者署名が必須） |
| 配布 | ストアの CDN | 自前の HTTPS 固定 URL |
| インストール | パッケージ導入 | サイレント導入が必須 |
| 自動更新 | ストアが担当 | アプリ側で実装 |
| 非公開 API の審査リスク | あり（個別判断） | あり（同じ） |
| 本アプリの実測 | コア機能が動作することを確認済み | 未検証 |

詳細・出典・未確認点は [docs/msix-verification.md](msix-verification.md) を参照。
**MSIX を選んでも審査通過は保証されません。** 非公開 API の扱いは提出時に個別判断となります。

## 4. ストア掲載素材

### 表示名

`Game Audio Manager`

### 短い説明（最大 100 文字程度）

- **日本語**: アプリごとに音声の出力先とミュートを切り替える常駐アプリ。ゲームの音だけ別のスピーカーへ。
- **English**: Route each app's audio to a different device and mute it independently. Runs in the tray.

### 詳細説明（日本語）

```
Game Audio Manager は、Windows のアプリ・ゲームごとに「どのスピーカーから音を出すか」と
「ミュートするか」を切り替える常駐アプリです。

■ できること
・起動中のアプリを一覧表示し、行ごとに出力先を変更
・アプリごとにミュートを切り替え（混在状態も表示）
・登録したアプリはトレイ常駐のまま出力先を自動で維持
・優先デバイスを複数登録し、接続状況に応じて自動で切り替え
・デバイスの抜き差しやスリープ復帰を検知して即座に再適用
・ダーク/ライト/システムテーマ、日本語/英語の切り替え

■ こんなときに
・ゲームの音だけヘッドホン、音楽はスピーカーから出したい
・通話中だけ特定のアプリをミュートしたい
・ディスプレイのスピーカーと USB スピーカーを使い分けたい

■ 注意
・出力先の変更は、対象アプリが次に音声セッションを作るときに反映されます
  （再生中の音は自動では移動しません）
・ウィンドウを持たないバックグラウンドアプリは一覧に出ないことがあります
・管理者権限は不要です
```

### 詳細説明（English）

```
Game Audio Manager routes each app's audio to the device you choose and mutes apps
independently. It stays in the tray, so the routing keeps working after you close the window.

- Per-app output device, with ordered fallback candidates
- Per-app mute, including a mixed-state indicator
- Automatic re-apply on app start, device reconnect and resume from sleep
- Dark / light / system theme, Japanese and English UI
- No administrator rights required

Note: Windows applies the output change when the app next creates an audio session;
audio that is already playing does not move automatically.
```

### 検索キーワード

`audio`, `sound`, `output device`, `per-app audio`, `mute`, `mixer`, `tray`,
`音声`, `出力先`, `ミュート`, `オーディオ`

### カテゴリ

ユーティリティ / マルチメディア（Utilities）

### ストア ロゴ・アイコン

| 用途 | ファイル | サイズ |
| --- | --- | --- |
| ストア掲載アイコン（Partner Center でアップロード） | `docs/images/store/store-icon-300.png` | 300×300 |
| パッケージ内ロゴ（マニフェストが参照） | `packaging/Package/Assets/StoreLogo.png` ほか | 50 / 44 / 150 |

### スクリーンショット

| 用途 | ファイル | サイズ |
| --- | --- | --- |
| 日本語・ライト | `docs/images/store/store-ja-light.png` | 1920×1080 |
| 日本語・ダーク | `docs/images/store/store-ja-dark.png` | 1920×1080 |
| 英語・ライト | `docs/images/store/store-en-light.png` | 1920×1080 |
| 英語・ダーク | `docs/images/store/store-en-dark.png` | 1920×1080 |

撮り直すときは:

```powershell
./scripts/publish.ps1 -Version 2.0.0
./scripts/capture-store-screenshots.ps1
```

ウィンドウを指定サイズ（既定 1920×1080）にしてから `PrintWindow` で撮り、
テーマと言語を切り替えながら 4 枚を出します。設定ファイルは自動でバックアップ・復元されます。
ストアは 1366×768 以上・最大 10 枚。

### サポート・法務

| 項目 | 値 |
| --- | --- |
| サポート URL | https://github.com/tonbiattack/game-audio-manager/issues |
| プライバシー ポリシー | `PRIVACY.md`（https://github.com/tonbiattack/game-audio-manager/blob/main/PRIVACY.md） |
| 著作権 | © 2026 tonbiattack |
| ライセンス | MIT（`LICENSE`） |

## 5. 公開までの状況

提出の手順そのものは [store-submission.md](store-submission.md) にまとめています。

- [x] MSIX の登録・起動・音声ルーティングの実測と記録（[msix-verification.md](msix-verification.md)）
- [x] 配布方式の決定（MSIX を採用、EXE/MSI 方式は不採用）
- [x] MSIX 対応の改修: `StartupTask`（自動起動）、設定の保存先、単一インスタンスのミューテックス
- [x] Publisher 名（Partner Center の正式値）をマニフェストへ反映（PFN の一致を実測）
- [x] ストア用スクリーンショットの撮り直し（1920×1080 × 4、`scripts/capture-store-screenshots.ps1`）
- [x] ストア掲載アイコン（300×300）の用意
- [x] プライバシーポリシーの用意（[PRIVACY.md](../PRIVACY.md)）
- [x] CI で MSIX を生成し、PR ごとにパッケージ生成を検証
- [ ] 署名済み MSIX のインストール検証（**管理者権限が必要**）
- [ ] Windows App Certification Kit の実行と結果記録（**管理者権限が必要**）
- [ ] 非公開 API 利用のストアポリシー確認（10.2.8 の「unsupported ways」に当たるかは**未確定**。
      提出時の個別判断。EarTrumpet の前例あり）
- [ ] Partner Center での入力と申請（**所有者の作業**。手順は store-submission.md）
