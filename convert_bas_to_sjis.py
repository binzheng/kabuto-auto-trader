#!/usr/bin/env python3
"""
Convert Excel VBA .bas files from UTF-8 to Shift-JIS encoding

Usage:
    python3 convert_bas_to_sjis.py --source <元フォルダ> --destination <変換先フォルダ>

Examples:
    # excel_vba_simplified/Module から excel_vba_sjis へ変換
    python3 convert_bas_to_sjis.py --source excel_vba_simplified/Module --destination excel_vba_sjis

    # ドライラン（確認のみ）
    python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --dry-run

    # 絵文字を代替テキストに自動変換
    python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --replace-emoji

Options:
    --source, -s        元フォルダ（UTF-8の.basファイルがあるフォルダ）
    --destination, -d   変換先フォルダ（Shift-JISの.basファイルを出力するフォルダ）
    --replace-emoji     絵文字を代替テキストに自動変換（推奨）
    --dry-run          実際には変換せず、確認のみ
"""

import os
import sys
import argparse
import re
from pathlib import Path
from typing import List, Tuple


# 絵文字から代替テキストへのマッピング
EMOJI_REPLACEMENTS = {
    '🧪': '[TEST]',
    '✅': '[OK]',
    '❌': '[ERROR]',
    '📋': '[INFO]',
    '🚀': '[PERF]',
    '💾': '[SAVE]',
    '📁': '[FOLDER]',
    '⚠️': '[WARNING]',
    '🔍': '[SEARCH]',
    '💡': '[TIP]',
}


def replace_emoji(text: str) -> Tuple[str, List[str]]:
    """
    Replace emojis with alternative text representations.

    Returns:
        Tuple of (modified text, list of replacements made)
    """
    replacements_made = []

    # Use the emoji mapping
    for emoji, replacement in EMOJI_REPLACEMENTS.items():
        if emoji in text:
            count = text.count(emoji)
            text = text.replace(emoji, replacement)
            replacements_made.append(f"{emoji} -> {replacement} ({count}x)")

    # Handle any remaining emoji characters (U+1F000 - U+1FFFF range)
    emoji_pattern = re.compile(r'[\U0001F000-\U0001FFFF]+')
    remaining_emojis = emoji_pattern.findall(text)
    if remaining_emojis:
        for emoji in set(remaining_emojis):
            count = text.count(emoji)
            text = emoji_pattern.sub('[EMOJI]', text)
            replacements_made.append(f"{emoji} -> [EMOJI] ({count}x)")

    return text, replacements_made


def find_bas_files(directory: Path) -> List[Path]:
    """Find all .bas files in the specified directory."""
    if not directory.exists():
        print(f"❌ Error: Directory '{directory}' does not exist")
        return []

    bas_files = list(directory.glob("*.bas"))
    return sorted(bas_files)


def convert_file(source_path: Path, dest_path: Path, replace_emojis: bool = False, dry_run: bool = False) -> Tuple[bool, str, List[str]]:
    """
    Convert a single file from UTF-8 to Shift-JIS.

    Args:
        source_path: 元ファイルパス（UTF-8）
        dest_path: 変換先ファイルパス（Shift-JIS）
        replace_emojis: 絵文字を代替テキストに置換
        dry_run: Trueの場合は実際には変換しない

    Returns:
        Tuple of (success: bool, message: str, replacements: List[str])
    """
    try:
        # Read as UTF-8
        with open(source_path, 'r', encoding='utf-8') as f:
            content = f.read()

        replacements = []

        # Replace emojis if requested
        if replace_emojis:
            content, replacements = replace_emoji(content)

        if dry_run:
            if replacements:
                return True, "Would convert with emoji replacement (dry-run)", replacements
            return True, "Would convert (dry-run)", replacements

        # Try to encode as Shift-JIS to catch any remaining problematic characters
        try:
            content.encode('cp932')
        except UnicodeEncodeError as e:
            # If encoding fails and we didn't replace emojis, suggest it
            if not replace_emojis:
                return False, f"❌ Contains characters not supported by Shift-JIS. Try --replace-emoji option.", []
            else:
                return False, f"❌ Error encoding to Shift-JIS even after emoji replacement: {e}", replacements

        # Write as Shift-JIS (cp932)
        with open(dest_path, 'w', encoding='cp932') as f:
            f.write(content)

        if replacements:
            return True, "✅ Converted with emoji replacement", replacements
        return True, "✅ Converted successfully", replacements

    except UnicodeDecodeError as e:
        return False, f"❌ Error reading as UTF-8: {e}", []

    except Exception as e:
        return False, f"❌ Unexpected error: {e}", []


def main():
    parser = argparse.ArgumentParser(
        description='Convert Excel VBA .bas files from UTF-8 to Shift-JIS encoding (folder to folder)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 convert_bas_to_sjis.py -s excel_vba_simplified/Module -d excel_vba_sjis --replace-emoji
  python3 convert_bas_to_sjis.py --source src --destination dest --dry-run
        """
    )
    parser.add_argument(
        '--source', '-s',
        required=True,
        help='元フォルダ（UTF-8の.basファイルがあるフォルダ）'
    )
    parser.add_argument(
        '--destination', '-d',
        required=True,
        help='変換先フォルダ（Shift-JISの.basファイルを出力するフォルダ）'
    )
    parser.add_argument(
        '--replace-emoji',
        action='store_true',
        help='絵文字を代替テキストに自動変換（例: 🧪 -> [TEST]）'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='実際には変換せず、確認のみ'
    )

    args = parser.parse_args()

    source_dir = Path(args.source)
    dest_dir = Path(args.destination)

    print("=" * 60)
    print("Excel VBA .bas File Encoding Converter")
    print("UTF-8 → Shift-JIS (cp932)")
    print("=" * 60)
    print()
    print(f"📂 元フォルダ: {source_dir}")
    print(f"📂 変換先フォルダ: {dest_dir}")

    if args.replace_emoji:
        print("🔧 絵文字置換: 有効")

    print()

    if args.dry_run:
        print("🔍 DRY RUN MODE - No files will be created")
        print()

    # Check source directory
    if not source_dir.exists():
        print(f"❌ Error: 元フォルダ '{source_dir}' が存在しません")
        sys.exit(1)

    # Find .bas files in source
    bas_files = find_bas_files(source_dir)

    if not bas_files:
        print(f"❌ No .bas files found in '{source_dir}'")
        sys.exit(1)

    print(f"📁 Found {len(bas_files)} .bas file(s) in '{source_dir}':")
    for f in bas_files:
        print(f"   - {f.name}")
    print()

    # Create destination directory if not dry-run
    if not args.dry_run:
        if not dest_dir.exists():
            print(f"📁 Creating destination directory: {dest_dir}")
            dest_dir.mkdir(parents=True, exist_ok=True)
            print()
        elif dest_dir.exists() and list(dest_dir.glob("*.bas")):
            print(f"⚠️  Warning: Destination directory already contains .bas files")
            print(f"   Existing files will be overwritten")
            print()

    # Convert each file
    success_count = 0
    fail_count = 0
    total_replacements = []

    for source_file in bas_files:
        dest_file = dest_dir / source_file.name

        print(f"Processing: {source_file.name}")
        print(f"  From: {source_file}")
        print(f"  To:   {dest_file}")

        success, message, replacements = convert_file(
            source_file,
            dest_file,
            replace_emojis=args.replace_emoji,
            dry_run=args.dry_run
        )

        print(f"  {message}")

        if replacements:
            print(f"  Emoji replacements:")
            for repl in replacements:
                print(f"    - {repl}")
            total_replacements.extend(replacements)

        if success:
            success_count += 1
        else:
            fail_count += 1
        print()

    # Summary
    print("=" * 60)
    print("Summary:")
    print(f"  ✅ Successfully converted: {success_count}")
    print(f"  ❌ Failed: {fail_count}")
    print(f"  📊 Total: {len(bas_files)}")

    if total_replacements:
        print(f"  🔧 Total emoji replacements: {len(total_replacements)}")

    print("=" * 60)

    if args.dry_run:
        print()
        print("💡 To perform actual conversion, run without --dry-run flag")
        if fail_count > 0 and not args.replace_emoji:
            print("   Try adding --replace-emoji option to handle emoji characters")
        print(f"   python3 convert_bas_to_sjis.py -s {args.source} -d {args.destination}" +
              (" --replace-emoji" if not args.replace_emoji and fail_count > 0 else ""))
    else:
        print()
        print(f"✅ Converted files saved to: {dest_dir}")

    if fail_count > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
