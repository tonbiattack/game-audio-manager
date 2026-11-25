# MSIX 検証: 現状と blocked の記録

最終更新: 2026-11-25

対象 Issue: #39（関連 #35）

## 結論

**MSIX のパッケージ生成までは成功。インストールと、パッケージ内からの音声ルーティングの実測は未実施。**

未検証である理由は環境の制約（後述）で、動作の成否を示すものではありません。
「MSIX 内でも動く」「Store 審査を通る」のいずれも**断定しません**。

## できたこと

| 項目 | 結果 |
| --- | --- |
| マニフェスト作成 | `packaging/Package/AppxManifest.xml` |
| アイコン素材 | `packaging/Package/Assets/`（44/150/Store ロゴ） |
| パッケージ生成 | ✅ 成功（`scripts/pack-msix.ps1`） |
| 生成物 | `artifacts/GameAudioManager.msix` 61.3 MB |
| 署名 | ✅ 成功（テスト用の自己署名証明書で `signtool sign`） |

パッケージには自己完結 EXE をそのまま格納しています（.NET ランタイム不要）。

### 実装中に判明した注意点

- **マニフェストに UTF-8 BOM を付けると `makeappx` が失敗する**
  （`0x80080204 The package manifest is not valid`）。BOM 無しで書く必要があります。
- バージョン差し替えに素朴な `Version="[0-9.]+"` を使うと **`MinVersion="…"` まで書き換わり**
  マニフェストが不正になります。`<Identity>` 要素に限定して置換しています。

## 未実施と、その理由

### インストールが失敗する（0x800B0109）

```
Add-AppxPackage : Deployment failed with HRESULT: 0x800B0109
アプリ パッケージまたはバンドルの署名のルート証明書は、信頼されている必要があります。
```

自己署名証明書を `Cert:\CurrentUser\TrustedPeople` に入れても解決しませんでした。
ルート証明書を信頼させる必要がありますが、この環境では次で止まりました。

```
Import-Certificate -CertStoreLocation 'Cert:\CurrentUser\Root'
→ この操作で UI は使用できません。
```

- 自己署名証明書を**信頼されたルート**に入れる操作は、同意 UI か管理者権限が必要
- 本セッションは非対話・承認プロンプト無効のため実行できない
- **回避策として証明書ストアを書き換えたり、管理者昇格を強行したりしていません**

テスト用に作成した証明書は `CurrentUser\My` / `TrustedPeople` から削除済みです。

### そのため未検証の項目

- MSIX 内からの出力先設定・リセット
- パッケージ外（Windows 設定・実音声セッション）への反映
- トレイ常駐・ログオン自動起動・更新・アンインストールの挙動
- WACK（Windows App Certification Kit）の結果
- 非公開 API 利用の Store ポリシー適合性

## 検証を完了させるための前提

次のいずれかが必要です。

1. **コード署名証明書**（OV 以上）を用意し、`LocalMachine\TrustedPeople` に信頼させる
   （インストールに管理者権限が必要）
2. 開発者モードを有効化した環境で、署名済みパッケージをサイドロード
3. 信頼済み証明書を持つ CI ランナー（または実機）で `Add-AppxPackage` を実行

### 手順（前提が揃った後）

```powershell
# 1. パッケージを生成
./scripts/publish.ps1 -Version 0.2.0
./scripts/pack-msix.ps1 -Version 0.2.0.0 -Publisher 'CN=<証明書のサブジェクト>'

# 2. 署名
signtool sign /fd SHA256 /a /f <pfx> /p <password> artifacts\GameAudioManager.msix

# 3. 信頼済みルートへ（管理者）
Import-Certificate -FilePath <cer> -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'

# 4. インストール
Add-AppxPackage -Path artifacts\GameAudioManager.msix

# 5. 検証: アプリから出力先を変更し、レジストリと実セッションを確認
Get-ChildItem 'HKCU:\Software\Microsoft\Multimedia\Audio\DefaultEndpoint' |
  ForEach-Object { $p = Get-ItemProperty $_.PSPath; "$($_.PSChildName)"; $p }
```

**仮説（未検証）**: 本アプリは `HKCU` に直接書かず音声ポリシー API を呼ぶため、
MSIX のレジストリ仮想化の影響を受けないと考えています。ただし
「パッケージ内から API を呼べるか」「OS がパッケージの識別子で設定を保存できるか」は
未確認で、**仮説のまま**です。

## Store の EXE / MSI 方式について

MSIX が使えない場合の代替として、Store には EXE/MSI の提出方式もありますが、
要件（署名、HTTPS 配布 URL、サイレント インストール、更新の管理）は時期により変わります。
**最新要件は申請直前に公式資料で確認する**必要があり、本ドキュメントでは断定しません。

いずれの方式でも、GitHub Releases の自己完結 EXE は維持します
（既存の出力先変更機能を削除しない方針）。
