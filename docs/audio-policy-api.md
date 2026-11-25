# 非公開 AudioPolicyConfig API: 検証マトリクスと既知の制限

最終更新: 2026-11-25

対象 Issue: #38（関連 #33 / #35、PR #37 / #41）

## 1. なぜ非公開 API を使うのか

アプリ別の出力先変更には、公開された Windows API が存在しません。
`Windows.Media.Internal.AudioPolicyConfig` の `SetPersistedDefaultAudioEndpoint` を使うのが
現実的な唯一の方法で、EarTrumpet と SoundVolumeView も同じ経路を使っています。

代償として、次のリスクを受け入れています。

- 文書化されていないため、Windows 更新で壊れうる
- IID が OS バージョンで変わる（実際に Microsoft が変更している）
- vtable のレイアウトが固定であることに依存する
- Store 審査での扱いが不明確

## 2. ABI の根拠（なぜこのスロット番号なのか）

`RoGetActivationFactory` が返すのは WinRT インターフェースポインタで、vtable の先頭は
`IInspectable` の 6 スロットです。

| スロット | メソッド |
| --- | --- |
| 0 | QueryInterface |
| 1 | AddRef |
| 2 | Release |
| 3 | GetIids |
| 4 | GetRuntimeClassName |
| 5 | GetTrustLevel |
| 6 〜 24 | 未使用の 19 メソッド |
| **25** | `SetPersistedDefaultAudioEndpoint` |
| **26** | `GetPersistedDefaultAudioEndpoint` |
| 27 | `ClearAllPersistedApplicationDefaultEndpoints` |

**この 19 個のダミー宣言を省くと壊れます。** 実際に計測した差:

| オフセット | Set の HRESULT | レジストリへの書き込み |
| --- | --- | --- |
| 6 + 19 | 0 | あり（3 ロール分） |
| 3 + 19 | 0 | **なし** |

HRESULT 0 を返したまま何も起きないため、テストで検出しないと「成功したのに反映されない」
という最も分かりにくい不具合になります。

### なぜ `[ComImport]` を使わないか

.NET（Core / 5 以降）は `ComInterfaceType.InterfaceIsIInspectable` のマーシャリングを
サポートしておらず、キャスト時に
`PlatformNotSupportedException: Marshalling as IInspectable is not supported in the .NET runtime`
を投げます。そのため関数ポインタで直接呼んでいます。

## 3. 検証マトリクス

「未検証」は成功を意味しません。断定を避けるため明示します。

| 環境 | ビルド | 設定 | リセット | 読み取り | 状態 |
| --- | --- | --- | --- | --- | --- |
| Windows 11 Pro | 10.0.26300 | ✅ 成功（3 ロール書き込み、UI から実行） | ✅ 成功（既定へ復帰） | ❌ 空を返す | **実測済み** |
| Windows 11 21H2 以降（他ビルド） | 不明 | 未検証 | 未検証 | 未検証 | **未検証** |
| Windows 11 21H2 未満 | 不明 | 未検証 | 未検証 | 未検証 | **未検証** |
| Windows 10 1803 以降 | 不明 | 未検証 | 未検証 | 未検証 | **未検証** |
| Windows 10 1803 未満 | — | 非対応（IID なし） | — | — | 想定 |
| MSIX パッケージ内 | 不明 | 未検証 | 未検証 | 未検証 | **未検証**（#39） |

このリポジトリの CI（GitHub Actions `windows-latest`）は**音声デバイスを持たない**ため、
上記の実測は手動で行っています。CI はデバイス不要のロジックのみを検証します。

### 実測の詳細（Windows 11 26300）

| 項目 | 結果 |
| --- | --- |
| `RoGetActivationFactory`（21H2 IID） | 成功 |
| 21H2 IID が使えない場合のフォールバック | 実装済み・未発動（このOSでは21H2 IIDが有効） |
| デバイス ID 形式 | 短い形式は E_INVALIDARG (0x80070057)、`\\?\SWD#MMDEVAPI#…` で成功 |
| 3 ロール書き込み | `000_000` / `001_000` / `002_000` を確認 |
| リセット | エンドポイント値が消え、次回セッションで既定へ |
| 再生中セッションの移動 | **移動しない**（設定は次回セッション生成時に効く） |
| 不定 PID の扱い | 起動中のプロセスすべてに対して書き込み |

## 4. 既知の制限と、そのときの挙動

### 4.1 読み取りが空を返す

`GetPersistedDefaultAudioEndpoint` は、設定が成功していても空の HSTRING を返すことがあります。

**挙動**: `null`（不明）を返します。推測値で埋めません。
UI の表示は**アプリ自身の設定**を正とし、OS 側の値は検証には使いません。

外部（Windows の設定画面や他ツール）で変更された場合、本アプリの設定表示はそれに追従しません。
これは「アプリ内の保存設定」と「OS の実値」を混同しないための意図的な分離です。

### 4.2 再生中のセッションは移動しない

Windows の仕様です。`svcl.exe` も同じでした。

**挙動**: 「設定を記録した」と「実際に反映された」を別に扱います。

- `RoutingResult.Recorded` … OS ストアへの書き込みに成功
- `RoutingResult.AppliedToLiveSession` … 常に `false`（現状の API では保証できない）

UI には「アプリが次に音声セッションを作るときに反映されます」と明示します。

### 4.3 API が使えない OS・失敗時

**挙動**: 例外を投げず、`IRoutingCapability.IsAvailable = false` として報告します。

- アプリ起動時に一度だけ「この Windows ビルドではアプリ別の出力先変更を利用できません
  （ミュートは利用できます）」と表示
- 各操作は `Recorded = false` とメッセージを返す
- **ミュート・デバイス列挙・他アプリの監視は継続**します（独立した機能のため）

単体テストで固定しています（`AudioPolicyConfigFailureTests`）。

### 4.4 3 ロールの部分失敗

**挙動**: いずれかのロールで HRESULT が非 0 なら、その PID は失敗として扱い、
次の PID へ進みます。1 つでも成功した PID があれば `Recorded = true` とし、
失敗した PID の HRESULT をメッセージに含めます。

### 4.5 複数 PID と PID 再利用

- 対象は**プロセス名で解決した全 PID** です（子プロセスから音を出すゲームに対応）
- PID 再利用は、設定がプロセス ID ではなく Windows 内部のアプリ識別に紐づくため、
  他アプリの設定を書き換えることはありません
- 監視側は「PID + 起動時刻」でプロセスの同一性を判定するため、PID 再利用を再起動として扱います

### 4.6 COM / HSTRING の解放

- ファクトリは使用後に `Release` を明示的に呼びます
- デバイス ID の HSTRING は `finally` で `WindowsDeleteString`
- 読み取りで受け取った HSTRING も同様
- 失敗経路でも解放されることをコードで保証しています

### 4.7 並行操作

- 監視スレッドと UI スレッドが同時に書き込む可能性があります
- 書き込みは「最後の操作が勝つ」で、同一アプリへの同時操作は UI 上で直列化されます
  （操作中はボタンを無効化）
- 監視はアプリごとに `try/catch` するため、1 アプリの失敗が他へ波及しません

## 5. 無関係なアプリの設定を変えないこと

`SetPreferredDevice` は、指定したプロセス名に一致する PID にのみ書き込みます。
`ClearAllPersistedApplicationDefaultEndpoints`（全アプリ消去）は**呼びません**。
リセットは対象 PID に対して `deviceId = null` を渡す方式です。

回帰確認は手順として docs に記載し、自動テストでは「未知のデバイス名を拒否する」
「起動していないアプリは変更しない」を固定しています。

```powershell
# 対象アプリの設定だけが変わったことを確認する
Get-ChildItem 'HKCU:\Software\Microsoft\Multimedia\Audio\DefaultEndpoint' |
  ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    "{0} -> {1} value(s)" -f $_.PSChildName,
      (($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -ne '(default)' }).Count)
  }
```

## 6. Store 審査について

**断言しません。** 非公開 API の利用が Store ポリシー上どう扱われるかは公式資料で確認できておらず、
MSIX 内での動作も未検証です（#39）。「審査を通る」「通らない」のいずれも現時点では保証しません。
