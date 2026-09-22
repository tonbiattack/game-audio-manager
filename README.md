# toggle-shiren-mute

Steam版『不思議のダンジョン 風来のシレン6 とぐろ島探検録』の音声を、Windows上で制御するPowerShellスクリプト集です。

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

## 動作環境

- Windows 10 / 11
- Windows PowerShell 5.1 または PowerShell 7系
- Steam版 風来のシレン6
