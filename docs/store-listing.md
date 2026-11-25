# ストア公開の準備

最終更新: 2026-11-25

対象 Issue: #35, #39

## 1. 現在の状態

| 項目 | 状態 |
| --- | --- |
| 自己完結 EXE（GitHub Releases） | ✅ 生成できる（`scripts/publish.ps1`） |
| リリース CI（タグ → ZIP → Release） | ✅ `.github/workflows/release.yml` |
| MSIX パッケージ生成 | ✅ `scripts/pack-msix.ps1` |
| MSIX への署名（自己署名） | ✅ `scripts/make-test-msix.ps1 -CreateDevCertificate` |
| MSIX のインストール | ❌ **未実施**（信頼登録に管理者権限が必要） |
| MSIX 内からの音声ルーティング実測 | ❌ **未実施**（インストール待ち） |
| Windows App Certification Kit | ❌ 未実施 |
| ストア掲載素材 | 🟡 下書きあり（本ドキュメント） |
| プライバシーポリシー | 🟡 下書きあり（本ドキュメント） |

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
Get-AppxPackage Tonbiattack.GameAudioManager | Select-Object PackageFullName
Start-Process shell:AppsFolder\Tonbiattack.GameAudioManager_<publisherId>!GameAudioManager

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
Get-AppxPackage Tonbiattack.GameAudioManager | Remove-AppxPackage
Get-ChildItem Cert:\LocalMachine\TrustedPeople |
  Where-Object { $_.Subject -eq 'CN=GameAudioManager-Dev' } | Remove-Item   # 管理者
./scripts/make-test-msix.ps1 -RemoveDevCertificate -CertificateThumbprint <thumbprint>
```

### 検証したい観点

- MSIX 内から `Windows.Media.Internal.AudioPolicyConfig` を呼べるか
- パッケージの識別子で設定が保存され、パッケージ外の Windows 設定画面から見えるか
- **仮説**: 本アプリは `HKCU` に直接書かないため、レジストリ仮想化の影響を受けない。
  → 実測で確認するまで「仮説」のまま扱う

## 3. 配布方式の比較（決定材料）

| 観点 | MSIX（Store） | EXE（自己完結・GitHub Releases） |
| --- | --- | --- |
| 署名費用 | Store 経由なら実質不要 | コード署名証明書が必要（未購入の方針） |
| SmartScreen | 出ない | 出る（未署名のため） |
| 自動更新 | Store が担当 | 手動（新 ZIP を展開して入れ替え） |
| 審査 | あり | なし |
| 非公開 API 利用 | ポリシー上の可否が不明 | 制約なし |
| 配布の手軽さ | 1 クリック | ZIP 展開 |

現時点の推奨は**二本立て**:

1. GitHub Releases の自己完結 EXE を主配布（審査不要・即配布）
2. MSIX は検証が通った時点で Store 申請用に生成できる状態にしておく

## 4. ストア掲載素材（下書き）

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

### スクリーンショット

| 用途 | ファイル |
| --- | --- |
| 日本語・ライト | `docs/images/dotnet-app-list.png` |
| 英語・ライト | `docs/images/dotnet-app-en.png` |
| 日本語・ダーク | `docs/images/dotnet-app-dark.png` |

ストア要件は 1920×1080 以上の PNG を推奨。現在の画像は 1200×720 のため、
申請時に**ウィンドウを最大化して撮り直す**必要がある（未対応）。

### プライバシーポリシー（下書き）

```
Game Audio Manager は、利用者の個人情報を収集しません。

・ネットワーク通信を行いません
・音声の内容を録音・送信しません
・設定は端末内（%LOCALAPPDATA%\GameAudioManager）にのみ保存します
・音声デバイスとアプリの情報は、出力先を切り替える目的でのみ、端末内で参照します

お問い合わせ: <リポジトリの Issues を記載>
```

## 5. 未完了（公開前に必要）

- [ ] MSIX のインストール検証（上記手順、管理者権限が必要）
- [ ] MSIX 内からのルーティング実測と結果記録
- [ ] Windows App Certification Kit の実行と結果記録
- [ ] 非公開 API 利用のストアポリシー確認（**未確認**。公開の可否を保証できない）
- [ ] ストア用スクリーンショットの解像度要件を満たす撮り直し
- [ ] Publisher 名（Partner Center の正式値）をマニフェストへ反映
- [ ] 実際の申請（所有者の承認後）
