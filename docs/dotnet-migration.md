# C# / .NET 10 + WPF 移行: 技術検証と現状

最終更新: 2026-11-25

対象 Issue: #33（移行）、#34（UI 刷新）、#35（Store 公開）

## 1. 最重要の検証結果: アプリ別出力先を svcl.exe なしで実現できるか

### 結論

**公開 API だけでは実現できない。現状は svcl.exe への依存が残り、これが Store 公開のブロッカーになる。**

### 確認したこと

アプリ別の出力先設定は、Windows が次のレジストリに保存している。

```
HKCU\Software\Microsoft\Multimedia\Audio\DefaultEndpoint\<hash>_0
  (既定)      = \Device\HarddiskVolume3\...\chrome.exe
  000_000      = \\?\SWD#MMDEVAPI#{0.0.0....}.{guid}#{e6327cad-...}
  000_000_p    = {8E647786-FD6A-4321-8406-EE187188BA9C}
```

- `<hash>` は実行ファイルパスから作られる**未公開のハッシュ**。CRC32 / FNV-1 / FNV-1a / DJB2 / SDBM を UTF-8・UTF-16LE・大小文字違いで試したが一致しなかった。
- 既存エントリの**読み取り**はハッシュ不要（`(既定)` のパスで照合できる）。本実装はここを使っている。
- **書き込み**はハッシュを計算できないため、`svcl.exe`（SoundVolumeCommandLine）に委譲している。svcl は未公開の `AudioPolicyConfig` 系インターフェースを内部で呼んでいる。

### 重要な誤解の訂正

**svcl.exe も「再生中の音声セッション」は移動しない。** 実測で確認した。

```
svcl /SetAppDefault "4- USB Audio Device" all powershell.exe   → exit 0
直後のセッションの出力先                                        → 変更なし
アプリを再起動後                                               → 新しい出力先に生成される
```

つまり設定は「次に音声セッションが作られたとき」に効く。UI では「設定済み」と「実際に反映済み」を区別する必要がある（#33 の要求どおり）。本実装は `RoutingResult.Recorded` / `AppliedToLiveSession` でこれを表現している。

### Store 公開への影響（#35 のブロッカー）

1. **外部 EXE の同梱**: `svcl.exe` を MSIX に同梱して審査を通すのは現実的でない。
2. **レジストリの仮想化**: MSIX パッケージのアプリが `HKCU` へ書くと、パッケージ専用の仮想ハイブへリダイレクトされる。**システムの AudioSrv からは見えない**ため、仮に書き込みを自前実装しても効かない。
3. 回避するには restricted capability `unvirtualizedResources` が必要で、Store では用途の正当性を求められる。

現時点の判断: **未解決のブロッカーとして記録し、公開を保証しない。** 代替案は次の2つ。

| 案 | 内容 | リスク |
| --- | --- | --- |
| A. Store 版は「出力先変更なし」 | ミュート・デバイス列挙・監視のみ提供 | 機能退行。ただし審査は通る見込み |
| B. 非 Store 配布に限定 | MSIX を使わず GitHub Releases の署名付き EXE | Store 公開の目的を満たさない |

推奨は A（Store 版）＋ B（フル機能版）の二本立て。ただし #35 の完了条件「Store から導入して主要機能を検証」を満たすには、主要機能の定義を確定させる必要がある。

## 2. 実装済みの範囲

```
src/GameAudioManager.Core/          net10.0-windows / 警告をエラー扱い / アナライザー有効
  Audio/AudioModels.cs              デバイス・セッション・ミュート状態・インターフェース
  Audio/Interop/AudioInterop.cs     Core Audio の COM 定義
  Audio/CoreAudioDeviceService.cs   再生エンドポイント列挙（名前・状態・既定判定）
  Audio/CoreAudioSessionService.cs  全エンドポイント・複数 PID・ミュート取得/設定
  Configuration/                    設定モデル・JSON 保存・旧 games.json 取り込み
  Routing/AppRoutingService.cs      出力先の読み取り（ネイティブ）と書き込み（svcl）
  Routing/DevicePriority.cs         優先順位・意思決定・並べ替え

src/GameAudioManager.App/           net10.0-windows / WPF
  MainWindow.xaml + MainViewModel   一覧型 UI、非同期更新、ミュート、出力先適用

tests/GameAudioManager.Core.Tests/  xUnit 39 件（デバイス不要）
```

### 実機で確認したこと（2026-11-25 / Windows 11 26300）

| 項目 | 結果 |
| --- | --- |
| エンドポイント列挙 | 19 件（うち Active 5）を名前・状態付きで取得 |
| 既定デバイス判定 | `ヘッドホン (2- soundcore Liberty 4 NC)` を正しく既定と判定 |
| 複数エンドポイントのセッション検出 | chrome の 2 セッション（2 デバイス）を検出 |
| ミュート切り替え | UI のボタンクリック → 2 セッションとも `Muted=True`、画面も「ミュート中」に更新 |
| ミュート解除 | 元に戻ることを確認 |
| GUI 起動 | 管理者権限なしで起動、日本語表示、DPI 対応マニフェスト適用 |
| 単体テスト | 39 件すべて成功 |

## 3. 未実装（#33 / #34 / #35 の残り）

### #33

- [ ] 出力先設定の**ネイティブ化**（上記ブロッカー。Store 版の機能範囲を決める必要がある）
- [ ] トレイ常駐の単一プロセス、明示終了、多重起動防止
- [ ] ログオン時自動起動（ユーザー選択式）
- [ ] イベント駆動（`IAudioSessionNotification` / `IMMNotificationClient`）。現状はタイマー更新のみ
- [ ] 切断・再接続時のフォールバックと復元の常駐処理
- [ ] 旧 PowerShell 版からの明示的な移行 UI とバックアップ
- [ ] xUnit の対象拡張（ルールエンジン・常駐の状態遷移）

### #34

- [ ] 自動切替 ON/OFF の行内トグル
- [ ] 優先デバイス順の詳細パネル（現状は先頭1件のみ保存）
- [ ] 検索・絞り込み
- [ ] 設定済み / 反映済み / 反映待ち / 失敗 の視覚的区別
- [ ] ダーク/ライト、キーボード操作、英語化
- [ ] スクリーンショットの README 掲載

### #35

- [ ] MSIX 構成、Partner Center の値、署名
- [ ] `svcl.exe` 問題の解決または機能範囲の確定（**公開ブロッカー**）
- [ ] Windows App Certification Kit の検証
- [ ] ストア掲載素材（日英）
- [ ] リリース CI での MSIX 生成

## 4. 手動確認手順（デバイスが必要な項目）

```powershell
# ビルドと起動
dotnet build GameAudioManager.sln -c Release
.\src\GameAudioManager.App\bin\Release\net10.0-windows\GameAudioManager.exe
```

1. 一覧に起動中のアプリが並ぶこと（シェル系ホストが混ざらないこと）
2. 出力先のドロップダウンに、接続中のデバイスだけが並ぶこと
3. アプリを選び「ミュートする」→ 実際に音が消え、行の表示が「ミュート中」になること
4. もう一度押して解除できること
5. 出力先を変えて「適用」→ 「次に音声セッションを作るときに反映されます」と表示されること
6. そのアプリを再起動し、実際に新しいデバイスから音が出ること
7. 「Windows の既定へ戻す」→ 再起動後に既定へ戻ること

## 5. 決定事項の記録

| 論点 | 決定 | 理由 |
| --- | --- | --- |
| 設定の保存先 | `%LOCALAPPDATA%\GameAudioManager\settings.json` | インストール先は書き込み不可（MSIX では特に）。管理者権限不要 |
| デバイスの識別 | MMDevice の ID を正とする | 名前は変更可能・重複しうる。#33 の要求どおり |
| セッションの照合 | PID ではなくプロセス名 | ゲームが子プロセスから音を出す場合に PID 一致では漏れる（#9 の実測） |
| ミュートの混在規則 | 1つでも解除されていれば全ミュート | CLI 版と揃え、状態が2値に収束する |
| ルーティングの書き込み | 当面 svcl.exe | 未公開 API。ハッシュを再現できない |
| Core の対象フレームワーク | `net10.0-windows` | Core Audio とレジストリが Windows 専用。テストも Windows CI で足りる |
