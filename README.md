# toggle-shiren-mute

Steam版『不思議のダンジョン 風来のシレン6 とぐろ島探検録』の音声を、Windows上でアプリ単位にミュート／解除するPowerShellスクリプトです。

## 使い方

1. シレン6を起動する
2. `toggle-shiren-mute.ps1` を実行する

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\toggle-shiren-mute.ps1
```

実行するたびに、シレン6のミュート状態が切り替わります。

```text
MUTE -> UNMUTE -> MUTE ...
```

## ショートカットから使う

Windowsのショートカットを作成し、リンク先を次のように設定すると便利です。

```text
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\path\to\toggle-shiren-mute.ps1"
```

## プロセスを自動検出できない場合

スクリプト冒頭の `$ProcessName` に、シレン6のプロセス名を指定してください。

プロセス名は次のコマンドで確認できます。

```powershell
Get-Process | Where-Object {
    $_.MainWindowTitle -like "*Shiren*" -or
    $_.MainWindowTitle -like "*シレン*"
} | Select-Object ProcessName, Id, MainWindowTitle
```

例:

```powershell
$ProcessName = "Shiren6"
```

空文字のままなら、ウィンドウタイトルから自動検出します。

## 注意

このツールは、Windowsのオーディオセッション上でシレン6だけをミュートします。

Bluetoothイヤホンとの接続自体を解除したり、Windowsの出力先を変更したりするものではありません。そのため、マルチポイント対応イヤホンの接続状態を解放したい場合は、Windows側の出力デバイスを別のデバイスへ切り替える必要があります。

## 動作環境

- Windows 10 / 11
- Windows PowerShell 5.1 または PowerShell 7系
- Steam版 風来のシレン6
