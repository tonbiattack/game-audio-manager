# game-audio-manager

Windows 上でゲームごとの音声を制御する PowerShell スクリプト集です。任意のゲームのプロセス名を指定して検出、ミュート切替、出力先変更を行えます。

## Windows GUI を使う

ゲームと出力先を選ぶだけで切り替える場合は、`game-audio-manager.ps1` を起動します。GUI は `config/games.json` の有効なゲームを表示し、接続中のデバイスを選べます。

初回だけ、サンプルを個人用設定としてコピーします。`games.json` は端末ごとのデバイス名を含むため Git には追加されません。

```powershell
Copy-Item .\config\games.example.json .\config\games.json
.\game-audio-manager.ps1
```

`優先デバイスを適用` は、各ゲームの `outputDevices` に書かれた順で、現在接続中の最初のデバイスを選びます。`選択したデバイスを適用` では、接続中の任意の出力先を指定できます。ゲームが起動していない場合は適用できません。

### ゲームを追加・変更する

`config/games.json` の `games` 配列へ次の形式で項目を追加します。`outputDevices` は左側ほど優先され、`enabled: false` のゲームは GUI に表示されません。

```json
{
  "name": "ゲーム名",
  "processName": "GameExecutableName",
  "outputDevices": [
    "第1候補のデバイス名",
    "第2候補のデバイス名"
  ],
  "enabled": true
}
```

プロセス名はゲームを起動して `detect-game-process.ps1 -ProcessName "候補名"` で確認します。デバイス名は `set-game-output.ps1 -List` の `指定値` をそのまま使ってください。

## 任意のゲームを操作する

ゲームの実行ファイル名（`.exe` は付けても省いても構いません）を `-ProcessName` に指定します。

```powershell
# プロセスを検出する
.\detect-game-process.ps1 -ProcessName "ExampleGame"

# 対象ゲームの音声セッションをミュート／解除する
.\toggle-game-mute.ps1 -ProcessName "ExampleGame"

# 使用できる出力先を確認する（ゲームが未起動でも実行可能）
.\set-game-output.ps1 -List

# 出力先を指定する
.\set-game-output.ps1 -ProcessName "ExampleGame" -Device "Realtek(R) Audio"

# Windows の既定出力へ戻す
.\set-game-output.ps1 -ProcessName "ExampleGame" -Reset
```

プロセスが見つからない場合、エラーには指定したプロセス名が表示されます。`detect-game-process.ps1` で実行中のプロセス名を確認してください。

### Slay the Spire 2（Steam版）

Steam版 Slay the Spire 2 のプロセス名は `SlayTheSpire2` です。次のコマンドで、ゲームだけを検出・ミュート・出力先変更できます。

```powershell
.\detect-game-process.ps1 -ProcessName "SlayTheSpire2"
.\toggle-game-mute.ps1 -ProcessName "SlayTheSpire2"
.\set-game-output.ps1 -ProcessName "SlayTheSpire2" -Device "使用するデバイス名"
.\set-game-output.ps1 -ProcessName "SlayTheSpire2" -Reset
```

出力先を選ぶ前に `set-game-output.ps1 -List` を実行し、表示された `指定値` を `-Device` に指定してください。

### Balatro（Steam版）

Steam版 Balatro のプロセス名は `Balatro` です。次のコマンドで、Balatro だけを検出・ミュート・出力先変更できます。

```powershell
.\detect-game-process.ps1 -ProcessName "Balatro"
.\toggle-game-mute.ps1 -ProcessName "Balatro"
.\set-game-output.ps1 -ProcessName "Balatro" -Device "使用するデバイス名"
.\set-game-output.ps1 -ProcessName "Balatro" -Reset
```

## 既存のシレン6用コマンドとの互換性

既存の `detect-shiren-process.ps1`、`toggle-shiren-mute.ps1`、`set-shiren-output.ps1` は引き続き利用できます。引数を指定しない場合は従来どおり `ShirenTheWanderer6` を対象にし、必要なら `-ProcessName` で上書きできます。

## シレン6の識別

Steam版シレン6の実行ファイルは `ShirenTheWanderer6.exe` です。

このリポジトリでは、ウィンドウタイトルではなく、この実行ファイル名を使ってシレン6を識別します。

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

## シレン6の出力先を変更する

アプリ単位の出力先変更には NirSoft の SoundVolumeCommandLine (`svcl.exe`) を利用します。

```powershell
.\set-shiren-output.ps1 -List
```

`指定値` 列の文字列を `-Device` に指定します。たとえばシレン6だけを Bluetooth イヤホン以外へ割り当てる場合:

```powershell
.\set-shiren-output.ps1 -Device "Realtek(R) Audio"
```

Windowsの既定出力へ戻す場合:

```powershell
.\set-shiren-output.ps1 -Reset
```

SoundVolumeCommandLine の全項目を CSV 形式で確認する場合:

```powershell
.\set-shiren-output.ps1 -RawList
```

### 出力先を自動で再設定する

固定したい出力先の `指定値` を使って監視を起動します。

```powershell
.\watch-shiren-output.ps1 -Device "4- HD Audio Driver for Display Audio"
```

複数の候補を指定する場合は、`|` で区切ります。左側ほど優先され、接続されている最初の候補が選ばれます。

```powershell
.\watch-shiren-output.ps1 -Device "4- HD Audio Driver for Display Audio|4- USB Audio Device|5- USB Audio Device"
```

監視中は、シレンの起動・再起動と指定デバイスの再接続を検出すると出力先を設定します。デバイスが未接続の間や設定に失敗した場合は、5秒ごとに再試行します。監視は `Ctrl+C` で終了できます。監視の開始時にもゲームとデバイスが利用可能なら設定します。デバイス名は `-List` で確認し、同じ指定値の有効なデバイスが複数ある場合は、一意に識別できる名前を選んでください。

ログイン時に自動開始するには、`Win + R` で `shell:startup` を開き、次をリンク先にしたショートカットを作成します。パスとデバイス名は自身の環境に合わせて変更してください。

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\apps\toggle-shiren-mute\watch-shiren-output.ps1" -Device "4- HD Audio Driver for Display Audio"
```

非表示で起動した監視を停止するには、タスク マネージャーの「詳細」タブで、コマンドラインに `watch-shiren-output.ps1` を含む PowerShell プロセスを終了します。自動起動をやめるには、作成したショートカットを削除します。非表示でのエラーは画面に表示されないため、設定を確認するときは上記のコマンドを通常の PowerShell で実行してください。

## プロセス名を明示的に変更する場合

通常は変更不要です。

実環境で別名になっている場合のみ指定できます。

```powershell
.\detect-shiren-process.ps1 -ProcessName "ActualProcessName"
.\set-shiren-output.ps1 -Device "Speakers" -ProcessName "ActualProcessName"
```

## 注意

`set-shiren-output.ps1` は NirSoft SoundVolumeCommandLine を使用します。このリポジトリには `svcl.exe` 本体を含めません。

まず `detect-shiren-process.ps1` でシレン6を正しく識別できることを確認してから、ミュートや出力先変更を試してください。

## 手動確認手順

実機のオーディオセッションと出力先は自動テストでは検証できないため、変更後は次を確認してください。

1. 対象ゲームを起動し、`detect-game-process.ps1 -ProcessName "実際のプロセス名"` で PID を確認する。
2. `toggle-game-mute.ps1 -ProcessName "実際のプロセス名"` を2回実行し、ミュートと解除が交互に切り替わることを確認する。
3. `set-game-output.ps1 -List` で有効なデバイス名を確認し、`-Device` で出力先を変更する。
4. `set-game-output.ps1 -ProcessName "実際のプロセス名" -Reset` で Windows の既定出力に戻す。
5. 存在しない名前を指定し、エラーにそのプロセス名が表示されることを確認する。

## 動作環境

- Windows 10 / 11
- Windows PowerShell 5.1 または PowerShell 7系
- Steam版 風来のシレン6
