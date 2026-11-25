# C# / .NET 10 + WPF 移行: 技術検証と現状

最終更新: 2026-11-25

対象 Issue: #33（移行）、#34（UI 刷新）、#35（Store 公開）

## 1. 最重要の検証結果: アプリ別出力先を svcl.exe なしで実現できるか

### 結論

**実現できた。`svcl.exe` への依存は解消済み。**

EarTrumpet と同じ `Windows.Media.Internal.AudioPolicyConfig` の
`SetPersistedDefaultAudioEndpoint` を使う。外部実行ファイルを必要としないため、
単一バイナリで配布できる。

### 実装の要点（ここを外すと「成功したのに何も起きない」）

1. **vtable オフセットは 6 + 19**

   WinRT インターフェースの先頭には `IInspectable` の 6 スロット
   （QueryInterface / AddRef / Release / GetIids / GetRuntimeClassName / GetTrustLevel）がある。
   `SetPersistedDefaultAudioEndpoint` はその後に 19 個の未使用メソッドが続く 20 番目。

   ```
   slot = 6 + 19 = 25   … SetPersistedDefaultAudioEndpoint
   slot = 6 + 20 = 26   … GetPersistedDefaultAudioEndpoint
   ```

   19 個のダミー宣言を省くと別メソッド（`add_RingerVibrateStateChanged`）を叩き、
   **HRESULT 0 を返したまま何も起きない**。EarTrumpet discussion #1543 の症状と同じ。

2. **.NET では `[ComImport]` + `InterfaceIsIInspectable` が使えない**

   .NET（Core）は `PlatformNotSupportedException: Marshalling as IInspectable is not
   supported in the .NET runtime` を投げる。関数ポインタで直接呼ぶ必要がある。

3. **デバイス ID は「短い形式」ではなくデバイスインターフェースパス**

   `IMMDevice::GetId` が返す `{0.0.0.…}.{guid}` をそのまま渡すと **E_INVALIDARG (0x80070057)**。
   API が要求するのは次の形式（`DefaultEndpoint` に保存される文字列と同じ）。

   ```
   \\?\SWD#MMDEVAPI#{0.0.0.00000000}.{guid}#{e6327cad-dcec-4949-ae8a-991e976a79d2}
   ```

   末尾はレンダー用デバイスインターフェースクラス GUID。キャプチャは
   `{2eef81be-33fa-4800-9670-1cd474972c3f}`。

4. **IID は OS バージョンで変わる**

   | OS | IID |
   | --- | --- |
   | Windows 10 21H2 以降 / Windows 11 | `ab3d4648-e242-459f-b02f-541c70306324` |
   | それ以前 | `2a59116d-6c4f-45e0-a74f-707e3fef9258` |

   21H2 の IID で `RoGetActivationFactory` を試し、失敗したら downlevel に落とす。

5. **3 つのロールすべてに設定する**

   Windows は role（console / multimedia / communications）ごとに別のエンドポイントを持つ。
   `multimedia` だけ設定すると、console ストリームは既定のままになる。
   `svcl.exe` と同じく 3 ロールすべてを書く。

### ハッシュ解析は不要だった

前回は `HKCU\...\DefaultEndpoint\<hash>_0` の `<hash>` を再現しようとして失敗したが、
**この API はハッシュを内部で処理するため解析そのものが不要**。読み取りも
`GetPersistedDefaultAudioEndpoint` で行える（ただし後述の既知問題あり）。

### 実機での検証結果（Windows 11 26300）

| 検証 | 結果 |
| --- | --- |
| `RoGetActivationFactory`（21H2 IID） | 成功（HRESULT 0） |
| vtable オフセット 6+19 での Set | 成功。レジストリに `000_000`/`001_000`/`002_000` が書かれる |
| vtable オフセット 3+19 での Set | **HRESULT 0 だが何も書かれない**（誤ったオフセットの症状を再現） |
| 短いデバイス ID での Set | E_INVALIDARG (0x80070057) |
| デバイスインターフェースパスでの Set | 成功 |
| `ResetToDefault`（deviceId = null） | 成功。レジストリのエンドポイント値が消え、既定に戻る |
| GUI の「適用」ボタン → レジストリ | 成功（3 ロールすべて） |

### 既知の問題

- **`GetPersistedDefaultAudioEndpoint` は値を返さない**（HRESULT 0 だが HSTRING が空）。
  EarTrumpet discussion #1543 でも同じ報告がある。読み取りは引き続きレジストリを
  直接見るほうが確実なので、UI の表示はアプリ自身の設定を正とする。
- **再生中のセッションは移動しない**（実測）。設定はストアに書かれ、**次に音声セッションが
  作られたとき**に効く。`svcl.exe` も同じ挙動だった。UI では
  「アプリが次に音声セッションを作るときに反映されます」と明示している。

## 2. MSIX と EXE / MSI の比較（#35）

`svcl.exe` 依存がなくなったことで、MSIX のレジストリ仮想化は**問題ではなくなった**
（自前の書き込みをしないため）。残る論点は配布形態と署名。

| 観点 | MSIX（Store） | MSIX（自前配布） | EXE（自己完結） | MSI |
| --- | --- | --- | --- | --- |
| 署名費用 | Store 経由なら実質不要（Microsoft が署名） | 証明書が必要 | 証明書が必要 | 証明書が必要 |
| 証明書 | 不要 | OV: 年 3〜5 万円程度 / EV: 年 5〜10 万円程度 | 同左 | 同左 |
| SmartScreen | 出ない | 出る（信頼されていない発行元） | 出る | 出る |
| 自動更新 | Store が担当 | 自前実装 | 自前実装 | 自前実装 |
| 審査 | あり（数日〜） | なし | なし | なし |
| インストール | ストアから 1 クリック | 証明書の信頼が必要な場合あり | 展開して実行のみ | 管理者権限が要ることがある |
| アンインストール | 標準 | 標準 | 手動（README に手順） | 標準 |
| 制約 | API 制限・仮想化・`unvirtualizedResources` の審査 | なし | なし | なし |
| 検証コスト | Windows App Certification Kit 必須 | 任意 | 任意 | 任意 |

### 判断

**出力先変更機能を削除する必要はなくなった。** ただし次のトレードオフがある。

- **Store 配布を主とする場合**: 署名費用が不要で SmartScreen の警告も出ない。審査と
  API 制限（将来 Microsoft が内部 API を塞ぐリスク）を受け入れる必要がある。
- **EXE 自己完結を主とする場合**: 審査なしで即配布でき、内部 API も自由に使える。
  ただし **コード署名証明書の継続費用**と、未署名時の SmartScreen 警告が問題になる。

現実的な選択肢は次の二本立て。

1. **GitHub Releases に自己完結 EXE**（`dotnet publish -r win-x64 --self-contained`）。
   .NET ランタイム不要で展開即実行。署名は将来の課題として明記。
2. **MSIX も生成できるようにしておく**（Store 申請用）。`svcl.exe` を持ち込まないので
   前回のブロッカーは解消済み。審査通過の見込みが立った段階で申請する。

署名費用・審査条件は変動するため、申請直前に再確認する。現時点では**金額を断定しない**。

## 3. 実装済みの範囲

```
src/GameAudioManager.Core/          net10.0-windows / 警告をエラー扱い / アナライザー有効
  Audio/        デバイス列挙、全エンドポイント・複数 PID のセッション、ミュート取得/設定
  Configuration/設定モデル、JSON 永続化、旧 games.json の取り込み
  Routing/      AudioPolicyConfigRoutingService（ネイティブなアプリ別出力先）
                DevicePriority（優先順位・意思決定・並べ替え）

src/GameAudioManager.App/           WPF。一覧型 UI、非同期更新、ミュート、出力先適用

tests/GameAudioManager.Core.Tests/  xUnit 42 件（デバイス不要）
.github/workflows/dotnet-tests.yml  build + test（windows-latest）
```

## 4. 未実装（#33 / #34 / #35 の残り）

### #33

- [ ] トレイ常駐の単一プロセス、明示終了、多重起動防止
- [ ] ログオン時自動起動（ユーザー選択式）
- [ ] イベント駆動化（`IMMNotificationClient` / `IAudioSessionNotification`）。現状はタイマーのみ
- [ ] 切断・再接続時のフォールバック／復元の常駐処理
- [ ] 旧 PowerShell 版からの移行 UI とバックアップ
- [ ] 常駐の状態遷移テスト

### #34

- [ ] 自動切替 ON/OFF の行内トグル
- [ ] 優先デバイス順の詳細パネル（現状は1件のみ適用）
- [ ] 検索・絞り込み
- [ ] 設定済み / 反映済み / 反映待ち / 失敗 の視覚的区別
- [ ] ダーク/ライト、キーボード操作、英語化

### #35

- [ ] 自己完結 EXE の発行設定と GitHub Releases への添付
- [ ] MSIX パッケージ構成（Store 申請用）
- [ ] Windows App Certification Kit の検証
- [ ] ストア掲載素材（日英）
- [ ] 署名方針の決定（費用対効果をふまえて）

## 5. 手動確認手順（デバイスが必要な項目）

```powershell
dotnet build GameAudioManager.slnx -c Release
.\src\GameAudioManager.App\bin\Release\net10.0-windows\GameAudioManager.exe
```

1. 一覧に起動中のアプリが並ぶこと（シェル系ホストが混ざらないこと）
2. 出力先のドロップダウンに、接続中のデバイスだけが並ぶこと
3. アプリを選び「ミュートする」→ 音が消え、行が「ミュート中」になること
4. 出力先を選んで「適用」→ レジストリに 3 ロール分書かれ、案内文が出ること

   ```powershell
   Get-ChildItem 'HKCU:\Software\Microsoft\Multimedia\Audio\DefaultEndpoint' |
     ForEach-Object { $p = Get-ItemProperty $_.PSPath
       if ($p.'(default)' -like '*<プロセス名>.exe*') { "$($_.PSChildName)"; $p } }
   ```

5. そのアプリを再起動し、実際に新しいデバイスから音が出ること
6. 「Windows の既定へ戻す」→ 再起動後に既定へ戻ること

## 6. 決定事項の記録

| 論点 | 決定 | 理由 |
| --- | --- | --- |
| アプリ別出力先の実装 | `AudioPolicyConfig` を vtable 直呼び | `svcl.exe` を同梱せずに済む。MSIX でも動く |
| 設定の保存先 | `%LOCALAPPDATA%\GameAudioManager\settings.json` | インストール先は書き込み不可。管理者権限不要 |
| デバイスの識別 | MMDevice ID（短い形式）を設定に保存し、API 呼び出し時にパスへ変換 | 名前は変更・重複しうる |
| セッションの照合 | プロセス名（PID ではない） | 子プロセスから音を出すゲームを取りこぼさない（#9） |
| ミュートの混在規則 | 1つでも解除されていれば全ミュート | CLI 版と揃え、状態が2値に収束する |
| ルーティングの反映タイミング | 「次に音声セッションを作るとき」と明示 | 実測。再生中セッションは移動しない |
| Core の対象フレームワーク | `net10.0-windows` | Core Audio とレジストリが Windows 専用 |
