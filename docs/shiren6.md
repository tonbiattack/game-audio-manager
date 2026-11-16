# シレン6 専用の手順（レガシー）

Steam 版『不思議のダンジョン 風来のシレン6 とぐろ島探検録』向けの手順です。
汎用の使い方は [README](../README.md) を参照してください。

シレン6 は現在 `config/games.json` に登録して汎用 GUI・常駐監視で扱うことを推奨します。
ここに残しているのは、旧リポジトリ名（`toggle-shiren-mute`）時代のコマンドを
そのまま使い続けたい場合の互換手順です。

## 置き場

| パス | 役割 |
| --- | --- |
| `detect-shiren-process.ps1` | ルート。`detect-game-process.ps1` への薄いラッパー |
| `toggle-shiren-mute.ps1` | ルート。`toggle-game-mute.ps1` への薄いラッパー |
| `set-shiren-output.ps1` | ルート。`set-game-output.ps1` への薄いラッパー |
| `watch-shiren-output.ps1` | ルート。`legacy/shiren6/watch-shiren-output.ps1` への薄いラッパー |
| `legacy/shiren6/watch-shiren-output.ps1` | シレン専用監視の実装（エントリポイント） |
| `legacy/shiren6/ShirenOutputWatch.ps1` | 監視の状態遷移・デバイス選択・ミューテックス（関数のみ） |

ルート直下に残しているのは、既存の実行方法を壊さないための互換ラッパーだけです。
シレン6 固有の実装は `legacy/shiren6/` にあります。

## シレン6の識別

Steam 版シレン6の実行ファイルは `ShirenTheWanderer6.exe` です。
このリポジトリでは、ウィンドウタイトルではなく、この実行ファイル名でシレン6を識別します。

まずシレン6を起動して、次を実行してください。

```powershell
.\detect-shiren-process.ps1
```

正常に検出できれば、次のような情報が表示されます。

```text
ProcessName          Id    MainWindowTitle    Path
-----------          --    ---------------    ----
ShirenTheWanderer6   1234  ...                C:\...\ShirenTheWanderer6.exe
```

検出できない場合は、現在開いているウィンドウ付きプロセス一覧も表示します。

## ミュートを切り替える

```powershell
.\toggle-shiren-mute.ps1
```

シレン6のプロセス `ShirenTheWanderer6` に紐づくオーディオセッションだけをミュート／解除します。

## 出力先を変更する

アプリ単位の出力先変更には NirSoft の SoundVolumeCommandLine (`svcl.exe`) を利用します。
同梱物は `vendor/svcl/` にあります。

```powershell
.\set-shiren-output.ps1 -List
```

`指定値` 列の文字列を `-Device` に指定します。たとえばシレン6だけを Bluetooth イヤホン以外へ割り当てる場合:

```powershell
.\set-shiren-output.ps1 -Device "Realtek(R) Audio"
```

Windows の既定出力へ戻す場合:

```powershell
.\set-shiren-output.ps1 -Reset
```

SoundVolumeCommandLine の全項目を CSV 形式で確認する場合:

```powershell
.\set-shiren-output.ps1 -RawList
```

## 出力先を自動で再設定する（レガシー監視）

固定したい出力先の `指定値` を使って監視を起動します。

```powershell
.\watch-shiren-output.ps1 -Device "4- HD Audio Driver for Display Audio"
```

複数の候補を指定する場合は、`|` で区切ります。左側ほど優先され、接続されている最初の候補が選ばれます。

```powershell
.\watch-shiren-output.ps1 -Device "4- HD Audio Driver for Display Audio|4- USB Audio Device|5- USB Audio Device"
```

監視中は、シレンの起動・再起動と指定デバイスの再接続を検出すると出力先を設定します。
デバイスが未接続の間や設定に失敗した場合は、5秒ごとに再試行します。監視は `Ctrl+C` で終了できます。
監視の開始時にもゲームとデバイスが利用可能なら設定します。
デバイス名は `-List` で確認し、同じ指定値の有効なデバイスが複数ある場合は、一意に識別できる名前を選んでください。

> **注意:** 汎用の常駐監視 (`watch-game-output.ps1`) とシレン専用監視で同じゲームを同時に監視すると、
> デバイス適用が競合します。シレン6を `config/games.json` に登録して汎用監視へ統合した後は、
> シレン専用の監視プロセスを停止してください。

### ログイン時に自動開始する

`Win + R` で `shell:startup` を開き、次をリンク先にしたショートカットを作成します。
パスとデバイス名は自身の環境に合わせて変更してください。

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\apps\game-audio-manager\watch-shiren-output.ps1" -Device "4- HD Audio Driver for Display Audio"
```

非表示で起動した監視を停止するには、タスク マネージャーの「詳細」タブで、
コマンドラインに `watch-shiren-output.ps1` を含む PowerShell プロセスを終了します。
自動起動をやめるには、作成したショートカットを削除します。
非表示でのエラーは画面に表示されないため、設定を確認するときは上記のコマンドを通常の PowerShell で実行してください。

## プロセス名を明示的に変更する場合

通常は変更不要です。実環境で別名になっている場合のみ指定できます。

```powershell
.\detect-shiren-process.ps1 -ProcessName "ActualProcessName"
.\set-shiren-output.ps1 -Device "Speakers" -ProcessName "ActualProcessName"
```

## 注意

`set-shiren-output.ps1` は NirSoft SoundVolumeCommandLine を使用します。
このリポジトリには未改変の 64-bit 配布物（`svcl.exe`、`svcl.chm`、`readme.txt`）を
`vendor/svcl/` に同梱しています。利用・再配布時の条件は
[Third-party notices](../THIRD_PARTY_NOTICES.md) を確認してください。

まず `detect-shiren-process.ps1` でシレン6を正しく識別できることを確認してから、
ミュートや出力先変更を試してください。
