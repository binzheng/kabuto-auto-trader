# Excel VBA ファイルエンコード変換ガイド

## 概要

Excel VBAの.basファイルをUTF-8からShift-JIS (cp932)に変換するスクリプトです。

フォルダ単位で変換し、元フォルダと変換先フォルダを分離することで、元ファイルを安全に保護します。

## 必要な理由

- Excel VBAエディタは日本語環境ではShift-JISエンコーディングを期待します
- UTF-8で保存されたファイルをインポートすると文字化けが発生する可能性があります
- このスクリプトで安全にエンコーディングを変換できます

---

## 使用方法

### 基本的な使い方

```bash
# フォルダ単位で変換（絵文字置換付き - 推奨）
python3 convert_bas_to_sjis.py \
  --source excel_vba_simplified/Module \
  --destination excel_vba_sjis \
  --replace-emoji
```

### オプション

| オプション | 短縮形 | 説明 |
|----------|--------|------|
| `--source` | `-s` | 元フォルダ（UTF-8の.basファイルがあるフォルダ）- **必須** |
| `--destination` | `-d` | 変換先フォルダ（Shift-JISの.basファイルを出力）- **必須** |
| `--replace-emoji` | なし | 絵文字を代替テキストに自動変換（推奨） |
| `--dry-run` | なし | 実際には変換せず、確認のみ |

---

## 実行例

### ステップ1: ドライラン（確認のみ）

```bash
python3 convert_bas_to_sjis.py \
  --source excel_vba_simplified/Module \
  --destination excel_vba_sjis \
  --dry-run
```

**出力例**:
```
============================================================
Excel VBA .bas File Encoding Converter
UTF-8 → Shift-JIS (cp932)
============================================================

📂 元フォルダ: excel_vba_simplified/Module
📂 変換先フォルダ: excel_vba_sjis

🔍 DRY RUN MODE - No files will be created

📁 Found 6 .bas file(s) in 'excel_vba_simplified/Module':
   - Module_API_Simple.bas
   - Module_Config_Simple.bas
   - Module_Logger_Simple.bas
   - Module_Main_Simple.bas
   - Module_Main_Simple_MockRSS.bas
   - Module_Standalone_Test.bas

Processing: Module_API_Simple.bas
  From: excel_vba_simplified/Module/Module_API_Simple.bas
  To:   excel_vba_sjis/Module_API_Simple.bas
  Would convert (dry-run)

...

============================================================
Summary:
  ✅ Successfully converted: 6
  ❌ Failed: 0
  📊 Total: 6
============================================================

💡 To perform actual conversion, run without --dry-run flag
   python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis
```

### ステップ2: 絵文字置換付きで実行（推奨）

```bash
python3 convert_bas_to_sjis.py \
  --source excel_vba_simplified/Module \
  --destination excel_vba_sjis \
  --replace-emoji
```

**出力例**:
```
============================================================
Excel VBA .bas File Encoding Converter
UTF-8 → Shift-JIS (cp932)
============================================================

📂 元フォルダ: excel_vba_simplified/Module
📂 変換先フォルダ: excel_vba_sjis
🔧 絵文字置換: 有効

📁 Found 6 .bas file(s) in 'excel_vba_simplified/Module':
   - Module_API_Simple.bas
   - Module_Config_Simple.bas
   - Module_Logger_Simple.bas
   - Module_Main_Simple.bas
   - Module_Main_Simple_MockRSS.bas
   - Module_Standalone_Test.bas

📁 Creating destination directory: excel_vba_sjis

Processing: Module_API_Simple.bas
  From: excel_vba_simplified/Module/Module_API_Simple.bas
  To:   excel_vba_sjis/Module_API_Simple.bas
  ✅ Converted successfully

Processing: Module_Config_Simple.bas
  From: excel_vba_simplified/Module/Module_Config_Simple.bas
  To:   excel_vba_sjis/Module_Config_Simple.bas
  ✅ Converted successfully

Processing: Module_Logger_Simple.bas
  From: excel_vba_simplified/Module/Module_Logger_Simple.bas
  To:   excel_vba_sjis/Module_Logger_Simple.bas
  ✅ Converted successfully

Processing: Module_Main_Simple.bas
  From: excel_vba_simplified/Module/Module_Main_Simple.bas
  To:   excel_vba_sjis/Module_Main_Simple.bas
  ✅ Converted successfully

Processing: Module_Main_Simple_MockRSS.bas
  From: excel_vba_simplified/Module/Module_Main_Simple_MockRSS.bas
  To:   excel_vba_sjis/Module_Main_Simple_MockRSS.bas
  ✅ Converted successfully

Processing: Module_Standalone_Test.bas
  From: excel_vba_simplified/Module/Module_Standalone_Test.bas
  To:   excel_vba_sjis/Module_Standalone_Test.bas
  ✅ Converted with emoji replacement
  Emoji replacements:
    - 🧪 -> [TEST] (4x)
    - ✅ -> [OK] (14x)
    - ❌ -> [ERROR] (4x)
    - 📋 -> [INFO] (1x)
    - 🚀 -> [PERF] (1x)

============================================================
Summary:
  ✅ Successfully converted: 6
  ❌ Failed: 0
  📊 Total: 6
  🔧 Total emoji replacements: 5
============================================================

✅ Converted files saved to: excel_vba_sjis
```

### ステップ3: 変換後のファイル確認

```bash
ls -la excel_vba_sjis/
```

**出力**:
```
total 104
drwxr-xr-x   8 h.tei  staff    256 Jan 10 15:03 .
drwxr-xr-x  27 h.tei  staff    864 Jan 10 15:03 ..
-rw-r--r--   1 h.tei  staff   5984 Jan 10 15:03 Module_API_Simple.bas
-rw-r--r--   1 h.tei  staff   1453 Jan 10 15:03 Module_Config_Simple.bas
-rw-r--r--   1 h.tei  staff   3228 Jan 10 15:03 Module_Logger_Simple.bas
-rw-r--r--   1 h.tei  staff   9697 Jan 10 15:03 Module_Main_Simple_MockRSS.bas
-rw-r--r--   1 h.tei  staff   6819 Jan 10 15:03 Module_Main_Simple.bas
-rw-r--r--   1 h.tei  staff  12536 Jan 10 15:03 Module_Standalone_Test.bas
```

---

## 絵文字置換マッピング

`--replace-emoji` オプションを使用すると、以下の絵文字が自動的に代替テキストに置換されます:

| 絵文字 | 代替テキスト | 用途 |
|--------|-------------|------|
| 🧪 | `[TEST]` | テスト関連 |
| ✅ | `[OK]` | 成功・完了 |
| ❌ | `[ERROR]` | エラー・失敗 |
| 📋 | `[INFO]` | 情報 |
| 🚀 | `[PERF]` | パフォーマンス |
| 💾 | `[SAVE]` | 保存 |
| 📁 | `[FOLDER]` | フォルダ |
| ⚠️ | `[WARNING]` | 警告 |
| 🔍 | `[SEARCH]` | 検索 |
| 💡 | `[TIP]` | ヒント |

その他の絵文字は `[EMOJI]` に置換されます。

### 絵文字置換の例

**変換前（UTF-8）**:
```vba
Debug.Print "🧪 Kabuto - Standalone Unit Test"
Debug.Print "✅ Test completed"
Debug.Print "❌ Test failed"
```

**変換後（Shift-JIS）**:
```vba
Debug.Print "[TEST] Kabuto - Standalone Unit Test"
Debug.Print "[OK] Test completed"
Debug.Print "[ERROR] Test failed"
```

---

## Excel VBAへのインポート

変換後のファイルをExcel VBAにインポート:

1. Excel VBAエディタを開く（Alt+F11）
2. ファイル → ファイルのインポート
3. `excel_vba_sjis` フォルダから変換済みの`.bas`ファイルを選択
4. OK

**文字化けせずに正しくインポートされます！**

---

## フォルダ構造

### 変換前

```
excel_vba_simplified/
└── Module/                    ← 元フォルダ（UTF-8）
    ├── Module_API_Simple.bas
    ├── Module_Config_Simple.bas
    ├── Module_Logger_Simple.bas
    ├── Module_Main_Simple.bas
    ├── Module_Main_Simple_MockRSS.bas
    └── Module_Standalone_Test.bas
```

### 変換後

```
excel_vba_simplified/
└── Module/                    ← 元フォルダ（UTF-8、変更なし）
    └── ...

excel_vba_sjis/                ← 変換先フォルダ（Shift-JIS）
├── Module_API_Simple.bas
├── Module_Config_Simple.bas
├── Module_Logger_Simple.bas
├── Module_Main_Simple.bas
├── Module_Main_Simple_MockRSS.bas
└── Module_Standalone_Test.bas
```

---

## エラーハンドリング

### エラー: 元フォルダが存在しない

```
❌ Error: 元フォルダ 'excel_vba_simplified/Module' が存在しません
```

**解決**: 正しいフォルダパスを指定してください

```bash
# 現在のディレクトリを確認
pwd

# フォルダが存在するか確認
ls -la excel_vba_simplified/Module/

# 正しいパスで実行
python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --replace-emoji
```

### エラー: Shift-JISでサポートされない文字

```
❌ Contains characters not supported by Shift-JIS. Try --replace-emoji option.
```

**原因**: ファイルに絵文字など、Shift-JISで表現できない文字が含まれています

**解決**: `--replace-emoji` オプションを追加してください

```bash
python3 convert_bas_to_sjis.py \
  -s excel_vba_simplified/Module \
  -d excel_vba_sjis \
  --replace-emoji
```

### 警告: 変換先フォルダに既にファイルがある

```
⚠️  Warning: Destination directory already contains .bas files
   Existing files will be overwritten
```

**動作**: 警告が表示されますが、処理は続行されます。既存のファイルは上書きされます。

**対処**: 既存のファイルを保持したい場合は、別のフォルダ名を指定してください

```bash
python3 convert_bas_to_sjis.py \
  -s excel_vba_simplified/Module \
  -d excel_vba_sjis_backup \
  --replace-emoji
```

---

## 注意事項

### フォルダ単位での変換

このスクリプトは**フォルダ全体**を変換します。個別ファイルの変換はサポートしていません。

### 元ファイルの保護

- 元フォルダ（`--source`）のファイルは**変更されません**
- 変換結果は変換先フォルダ（`--destination`）に出力されます
- 元ファイルは安全に保護されます

### Git管理

変換先フォルダ（`excel_vba_sjis`）は生成物なので、`.gitignore`に追加することを推奨します:

```bash
echo "excel_vba_sjis/" >> .gitignore
```

**理由**:
- 変換先フォルダはいつでも再生成できます
- 元のUTF-8ファイル（`excel_vba_simplified/Module/`）のみをGit管理
- リポジトリのサイズを削減

---

## トラブルシューティング

### Q1: 変換したファイルをExcelにインポートしても文字化けする

**A1**: 以下を確認してください:
1. `--replace-emoji` オプションを使用したか
2. 変換先フォルダ（`excel_vba_sjis`）から正しいファイルをインポートしたか
3. Excelのロケール設定が日本語になっているか

### Q2: 元の状態に戻したい

**A2**: 変換先フォルダを削除するだけです:

```bash
rm -rf excel_vba_sjis
```

元フォルダ（`excel_vba_simplified/Module/`）は変更されていないので、再度変換できます。

### Q3: 一部のファイルだけ変換したい

**A3**: 一時的なフォルダにファイルをコピーして変換してください:

```bash
# 一時フォルダ作成
mkdir temp_vba

# 特定のファイルをコピー
cp excel_vba_simplified/Module/Module_API_Simple.bas temp_vba/
cp excel_vba_simplified/Module/Module_Logger_Simple.bas temp_vba/

# 変換
python3 convert_bas_to_sjis.py -s temp_vba -d excel_vba_sjis --replace-emoji

# クリーンアップ
rm -rf temp_vba
```

### Q4: スクリプトが見つからない

```bash
# スクリプトが存在するか確認
ls -la convert_bas_to_sjis.py

# 実行権限を確認
chmod +x convert_bas_to_sjis.py

# フルパスで実行
python3 /Users/h.tei/Workspace/source/python/kabuto/convert_bas_to_sjis.py -s ... -d ...
```

---

## ワークフロー例

### 開発ワークフロー

```bash
# 1. UTF-8ファイルを編集（元フォルダ）
vi excel_vba_simplified/Module/Module_Main_Simple.bas

# 2. Gitにコミット
git add excel_vba_simplified/Module/Module_Main_Simple.bas
git commit -m "Update main module"

# 3. Shift-JISに変換
python3 convert_bas_to_sjis.py \
  -s excel_vba_simplified/Module \
  -d excel_vba_sjis \
  --replace-emoji

# 4. Excel VBAにインポート
# excel_vba_sjis/Module_Main_Simple.bas をExcelにインポート

# 5. 変換先フォルダはクリーンアップ可能（任意）
rm -rf excel_vba_sjis
```

### チーム開発ワークフロー

```bash
# リポジトリをクローン
git clone <repository-url>
cd kabuto

# UTF-8ファイルは既にリポジトリに含まれています
ls excel_vba_simplified/Module/

# 各開発者がローカルでShift-JISに変換
python3 convert_bas_to_sjis.py \
  -s excel_vba_simplified/Module \
  -d excel_vba_sjis \
  --replace-emoji

# Excel VBAにインポート
# excel_vba_sjis/*.bas をExcelにインポート

# 変更を加えてGitにプッシュ（UTF-8ファイルのみ）
git add excel_vba_simplified/Module/*.bas
git commit -m "Update VBA modules"
git push
```

---

## まとめ

### 推奨コマンド

```bash
python3 convert_bas_to_sjis.py \
  --source excel_vba_simplified/Module \
  --destination excel_vba_sjis \
  --replace-emoji
```

### フォルダ単位変換の利点

| 項目 | 説明 |
|-----|------|
| 安全性 | 元ファイルを変更しません |
| 効率性 | フォルダ全体を一度に変換 |
| 管理性 | UTF-8とShift-JISを分離管理 |
| 再現性 | いつでも再変換可能 |

### 標準フォーマット

```
元フォルダ (UTF-8):        excel_vba_simplified/Module/
                              ↓ 変換
変換先フォルダ (Shift-JIS): excel_vba_sjis/
```

### 変換対象ファイル

- Module_API_Simple.bas
- Module_Config_Simple.bas
- Module_Logger_Simple.bas
- Module_Main_Simple.bas
- Module_Main_Simple_MockRSS.bas
- Module_Standalone_Test.bas

---

## 関連ドキュメント

- `BAS_ENCODING_README.md` - クイックスタートガイド
- `excel_vba_simplified/LOGGING_GUIDE.md` - ログ出力ガイド
- `EXCEL_ONLY_TEST.md` - Excel単体テストガイド

---

**作成日**: 2026-01-10
**更新日**: 2026-01-10
**バージョン**: 2.0.0
