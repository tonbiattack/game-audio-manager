# toggle-shiren-mute

Steam版『不思議のダンジョン 風来のシレン6 とぐろ島探検録』の音声を、Windows上で制御するPowerShellスクリプト集です。

現在は次の2通りに対応しています。

- シレン6だけをミュート／解除する
- シレン6だけを別のオーディオ出力先へ割り当てる

BluetoothイヤホンをPCとスマートフォンの2台へ接続しているとき、単にPC側でシレン6をミュートしただけでは、シレン6の音声セッションが残り、イヤホンがPC側へ切り替わる場合があります。

その場合は、シレン6の出力先そのものをBluetoothイヤホン以外へ変更する方法が有効です。

## ミュートを切り替える

シレン6を起動してから実行します。

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\toggle-shiren-mute.ps1
```

実行するたびに切り替わります。

```text
MUTE -> UNMUTE -> MUTE ...
```

## シレン6の出力先を変更する

アプリ単位の出力先変更には NirSoft の SoundVolumeCommandLine (`svcl.exe`) を利用します。

1. SoundVolumeCommandLine を入手する
2. `svcl.exe` をこのリポジトリのスクリプトと同じディレクトリへ置く
3. 使用できるデバイスを確認する

```powershell
.\set-shiren-output.ps1 -List
```

4. シレン6の出力先を、モニターやスピーカーなどBluetooth以外へ変更する

```powershell
.\set-shiren-output.ps1 -Device "Speakers"
```

同名デバイスが複数ある場合は、`-List` の結果に表示される Command-Line Friendly ID や Item ID を指定してください。

例:

```powershell
.\set-shiren-output.ps1 -Device "Realtek High Definition Audio\Device\Speakers\Render"
```

Windowsの既定出力へ戻す場合:

```powershell
.\set-shiren-output.ps1 -Reset
```

## svcl.exe を別の場所に置く場合

```powershell
.\set-shiren-output.ps1 -Device "Speakers" -SvclPath "C:\Tools\svcl.exe"
```

## プロセスを自動検出できない場合

両スクリプトとも、基本的にはウィンドウタイトルからシレン6を自動検出します。

出力先変更スクリプトでは明示指定もできます。

```powershell
.\set-shiren-output.ps1 -Device "Speakers" -ProcessName "Shiren6"
```

プロセス名は次のコマンドで確認できます。

```powershell
Get-Process | Where-Object {
    $_.MainWindowTitle -like "*Shiren*" -or
    $_.MainWindowTitle -like "*シレン*"
} | Select-Object ProcessName, Id, MainWindowTitle
```

## どちらを使うべきか

単にゲーム音を消したいだけなら `toggle-shiren-mute.ps1` で十分です。

Bluetoothマルチポイント利用時に、ミュートしているシレン6へイヤホン側の音声接続が奪われる場合は、`set-shiren-output.ps1` でシレン6をBluetooth以外の出力先へ割り当てる方法を試してください。

## 注意

`set-shiren-output.ps1` は外部ツールとして NirSoft SoundVolumeCommandLine を使用します。このリポジトリには `svcl.exe` 本体を含めません。

出力先変更はWindowsのアプリ別オーディオ設定として保存されるため、元に戻したい場合は `-Reset` を実行してください。

## 動作環境

- Windows 10 / 11
- Windows PowerShell 5.1 または PowerShell 7系
- Steam版 風来のシレン6
