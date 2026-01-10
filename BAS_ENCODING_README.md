# .basファイル エンコード変換スクリプト

## 作成したファイル

### 1. `convert_bas_to_sjis.py`
Excel VBAの.basファイルをUTF-8からShift-JIS (cp932)に変換するPythonスクリプト

フォルダ単位で変換し、元フォルダと変換先フォルダを指定できます。

---

## クイックスタート

### ステップ1: ドライラン（確認のみ）

```bash
cd /Users/h.tei/Workspace/source/python/kabuto
python3 convert_bas_to_sjis.py --source excel_vba_simplified/Module --destination excel_vba_sjis --dry-run
```

**結果**: 6個の.basファイルが検出され、変換対象として表示されます（実際には変更されません）

### ステップ2: 絵文字置換付きで実行（推奨）

```bash
python3 convert_bas_to_sjis.py --source excel_vba_simplified/Module --destination excel_vba_sjis --replace-emoji
```

**結果**:
- 全ての.basファイルが`excel_vba_sjis`フォルダにShift-JIS形式で変換されます
- 絵文字は自動的に代替テキストに置換されます（🧪 -> [TEST]、✅ -> [OK] など）
- 元のファイルは変更されません

### ステップ3: 変換されたファイルを確認

```bash
ls -la excel_vba_sjis/
```

**出力**:
```
Module_API_Simple.bas
Module_Config_Simple.bas
Module_Logger_Simple.bas
Module_Main_Simple.bas
Module_Main_Simple_MockRSS.bas
Module_Standalone_Test.bas
```

### ステップ4: Excel VBAにインポート

1. Excel VBAエディタを開く（Alt+F11）
2. ファイル → ファイルのインポート
3. `excel_vba_sjis`フォルダから.basファイルを選択
4. 日本語コメントが正しく表示されることを確認

---

## 使用方法

### 基本コマンド

```bash
python3 convert_bas_to_sjis.py --source <元フォルダ> --destination <変換先フォルダ>
```

### オプション

| オプション | 短縮形 | 説明 |
|----------|--------|------|
| `--source` | `-s` | 元フォルダ（UTF-8の.basファイルがあるフォルダ） |
| `--destination` | `-d` | 変換先フォルダ（Shift-JISの.basファイルを出力するフォルダ） |
| `--replace-emoji` | なし | 絵文字を代替テキストに自動変換（推奨） |
| `--dry-run` | なし | 実際には変換せず、確認のみ |

---

## 実行例

### 例1: 基本的な変換

```bash
python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis
```

### 例2: 絵文字置換付き変換（推奨）

```bash
python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --replace-emoji
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

### 例3: ドライラン（確認のみ）

```bash
python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --dry-run
```

---

## 絵文字置換マッピング

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

---

## 対象ファイル

excel_vba_simplified/Module/ ディレクトリ内の6個のファイル:
- Module_API_Simple.bas
- Module_Config_Simple.bas
- Module_Logger_Simple.bas
- Module_Main_Simple.bas
- Module_Main_Simple_MockRSS.bas
- Module_Standalone_Test.bas

---

## トラブルシューティング

### エラー: 元フォルダが存在しません

```
❌ Error: 元フォルダ 'excel_vba_simplified/Module' が存在しません
```

**解決**: 正しいフォルダパスを指定してください

```bash
# 現在のディレクトリを確認
pwd

# フォルダが存在するか確認
ls -la excel_vba_simplified/Module/
```

### エラー: Shift-JISでサポートされない文字

```
❌ Contains characters not supported by Shift-JIS. Try --replace-emoji option.
```

**解決**: `--replace-emoji` オプションを追加してください

```bash
python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --replace-emoji
```

### 変換先フォルダに既にファイルがある

```
⚠️  Warning: Destination directory already contains .bas files
   Existing files will be overwritten
```

**動作**: 警告が表示されますが、処理は続行されます。既存のファイルは上書きされます。

**対処**: 既存のファイルを保持したい場合は、別のフォルダ名を指定してください

```bash
python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis_backup --replace-emoji
```

---

## 元フォルダと変換先フォルダの分離

このスクリプトは**フォルダ単位**で変換します。

### メリット

1. **元ファイルを保護**: 元のUTF-8ファイルは変更されません
2. **比較が容易**: 元フォルダと変換先フォルダを比較できます
3. **再変換が簡単**: 元ファイルを修正して再変換できます

### ワークフロー

```
excel_vba_simplified/Module/  ← UTF-8 (元ファイル、Git管理)
         ↓ 変換
excel_vba_sjis/               ← Shift-JIS (Excel VBAインポート用)
```

---

## Gitとの連携

### 推奨: 変換先フォルダを.gitignoreに追加

```bash
echo "excel_vba_sjis/" >> .gitignore
```

**理由**:
- 変換先フォルダは生成物なのでGit管理不要
- 元のUTF-8ファイル（excel_vba_simplified/Module/）のみをGit管理
- 必要な時に再変換すればOK

### ワークフロー例

```bash
# 1. UTF-8ファイルを編集
vi excel_vba_simplified/Module/Module_Main_Simple.bas

# 2. Git にコミット
git add excel_vba_simplified/Module/Module_Main_Simple.bas
git commit -m "Update main module"

# 3. Shift-JISに変換
python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --replace-emoji

# 4. Excel VBAにインポート
# excel_vba_sjis/Module_Main_Simple.bas をExcelにインポート
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

### 所要時間

- 変換処理: 数秒
- 合計: **約5秒**

### 特徴

- ✅ フォルダ単位で変換
- ✅ 元ファイルを保護
- ✅ 絵文字を自動置換
- ✅ Shift-JIS互換
- ✅ Excel VBAで文字化けなし

---

**作成日**: 2026-01-10
**バージョン**: 2.0.0
