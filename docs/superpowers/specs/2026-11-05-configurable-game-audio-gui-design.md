# Configurable game-audio GUI — design

## Intent

PowerShell コマンドを覚えずに、ゲームごとの音声出力先を Windows GUI から変更できるようにする。ゲームの追加や候補デバイスの優先順変更は、スクリプトを編集せず設定ファイルだけで行えるようにする。

## Goals

- `config/games.json` のゲーム定義を読み、`enabled: true` のゲームだけを GUI に表示する。
- `name`、`processName`、`outputDevices`、`enabled` を持つ設定で、ゲームを追加・無効化できる。
- GUI から、起動中かどうか、接続中のデバイス、適用結果を表示する。
- 候補順の先頭で利用可能なデバイスを「優先デバイス」として適用し、必要なら接続中デバイスを明示選択できる。
- 既存の `set-game-output.ps1` を唯一の出力変更経路として使う。

## Non-goals

- 常駐トレイアプリ、ログイン時自動起動、多ゲーム監視、音量・ミュートの GUI 操作は実装しない。
- `games.json` の GUI 編集は行わない。ユーザーは JSON を直接編集する。
- 実機のゲーム再起動やデバイス接続は自動化しない。

## Approaches

1. GUI にゲームとデバイスを固定で書く。早いが、ゲーム追加のたびにスクリプト修正が必要になる。
2. `games.json` を読み込む WinForms GUI とし、既存の出力コマンドを子プロセスで呼ぶ。**選択:** 設定だけで追加でき、既存の音声制御・エラー処理を再利用できる。
3. 常駐トレイアプリと自動切替を同時に作る。便利だが、常駐管理と状態同期が増えるため本件には過剰。

## Configuration

コミットする `config/games.example.json` は、Shiren 6、Slay the Spire 2、Balatro の例を持つ。個人用の `config/games.json` は `.gitignore` に入れ、初回起動時にサンプルからコピーするよう案内する。ユーザー環境の候補デバイスは `outputDevices` 配列へ優先順で記述する。

設定読込は `lib/GameAudio.Config.ps1` に置く。必須文字列、空の候補、ゲーム名の重複、プロセス名の重複を明示的に拒否する。`Get-GameConfiguration` は検証済みのゲーム配列を返し、`Get-PreferredConfiguredDevice` は接続中デバイスとの最初の一致を返す。

## GUI

新しい `game-audio-manager.ps1` は Windows Forms で小さな単一ウィンドウを開く。ゲーム選択、ゲームの起動状態、接続中デバイスの選択欄、優先候補の説明、`優先デバイスを適用`、`選択したデバイスを適用`、`Windows の既定へ戻す`、更新ボタン、状態表示を持つ。

出力変更は子プロセスで `set-game-output.ps1` を呼び、その終了コードと標準出力／標準エラーを状態欄へ表示する。スクリプトの既定 `SvclPath` はパラメータ評価後に解決し、Windows PowerShell 5.1 からの起動でもリポジトリ直下の `svcl.exe` を使う。

ゲーム未起動時は適用ボタンを無効化し、対象ゲームを起動するよう表示する。優先候補がすべて未接続なら、適用せず候補名を表示する。

## Verification

設定読込・必須項目・重複・無効値・候補優先順を PowerShell テストで固定する。GUI のロジックは関数として分離し、起動中／未起動と、優先適用／明示選択の選択結果をテストする。実機では Balatro を使い、GUI から候補デバイスへ設定後にゲーム再起動を行い、`svcl.exe` のアクティブなアプリ音声セッションで確認する。
