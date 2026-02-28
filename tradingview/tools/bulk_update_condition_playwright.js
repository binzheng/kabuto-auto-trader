#!/usr/bin/env node
/**
 * TradingView Alert Condition Bulk Updater (Playwright)
 * アラートの条件（ストラテジー/インジケーター）バージョンを一括変更
 *
 * 使用方法:
 *   node tradingview/tools/bulk_update_condition_playwright.js
 *   node tradingview/tools/bulk_update_condition_playwright.js --dry-run --max-updates=5
 *   node tradingview/tools/bulk_update_condition_playwright.js --from-version=v4.0 --to-version=v7.0
 *
 * 主なオプション:
 *   --from-version=v4.0   変更前のバージョン文字列（デフォルト: v4.0）
 *   --to-version=v7.0     変更後のバージョン文字列（デフォルト: v7.0）
 *   --dry-run             クリックせず対象検出のみ
 *   --max-updates=20      最大更新件数
 *   --url=...             起動URL（デフォルト: Kabuto v7.0 適用チャート）
 *   --profile=...         ログインセッション保存先（他スクリプトと共通）
 *   --channel=chrome      システムChromeを使用
 *   --headless            ヘッドレス実行（通常は非推奨）
 */

const path = require("path");
const readline = require("readline");

const ITEM_XPATH_TEMPLATE = "//*[@id='id_alert-widget-tabs-slots_tabpanel_list']/div[2]/div[2]/div/div[{index}]";
const LIST_CONTAINER_XPATH = "//*[@id='id_alert-widget-tabs-slots_tabpanel_list']/div[2]/div[2]/div";
const ESTIMATED_ROW_HEIGHT = 55;

// Kabuto v7.0 が適用されているチャート
const DEFAULT_URL = "https://jp.tradingview.com/chart/2TEyPaCa/?symbol=TSE%3A9984";

function parseArgs(argv) {
  const args = {
    dryRun: false,
    maxUpdates: 20,
    betweenClicksMs: 1000,
    modalWaitMs: 1200,
    url: DEFAULT_URL,
    headless: false,
    profile: ".tv-playwright-profile",
    channel: "",
    stealth: true,
    keepOpenOnError: true,
    fromVersion: "v4.0",
    toVersion: "v7.0",
  };

  for (const arg of argv) {
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--headless") args.headless = true;
    else if (arg === "--headed") args.headless = false;
    else if (arg === "--no-stealth") args.stealth = false;
    else if (arg === "--close-on-error") args.keepOpenOnError = false;
    else if (arg.startsWith("--max-updates=")) args.maxUpdates = Number(arg.split("=")[1]);
    else if (arg.startsWith("--between-clicks-ms=")) args.betweenClicksMs = Number(arg.split("=")[1]);
    else if (arg.startsWith("--modal-wait-ms=")) args.modalWaitMs = Number(arg.split("=")[1]);
    else if (arg.startsWith("--url=")) args.url = arg.substring("--url=".length);
    else if (arg.startsWith("--profile=")) args.profile = arg.substring("--profile=".length);
    else if (arg.startsWith("--channel=")) args.channel = arg.substring("--channel=".length);
    else if (arg.startsWith("--from-version=")) args.fromVersion = arg.substring("--from-version=".length);
    else if (arg.startsWith("--to-version=")) args.toVersion = arg.substring("--to-version=".length);
  }

  return args;
}

function waitForEnter(message) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(`${message}\n`, () => { rl.close(); resolve(); });
  });
}

function buildItemXPath(template, index) {
  return template.includes("{index}")
    ? template.replaceAll("{index}", String(index))
    : template.replace(/\[\d+\]$/, `[${index}]`);
}

(async () => {
  const options = parseArgs(process.argv.slice(2));

  console.log(`[INFO] 条件を "${options.fromVersion}" → "${options.toVersion}" に一括変更します`);
  console.log(`[INFO] チャートURL: ${options.url}`);

  let playwright;
  try {
    playwright = require("playwright");
  } catch (_) {
    console.error("[ERROR] playwright が見つかりません: npm install playwright");
    process.exit(1);
  }

  const { chromium } = playwright;
  const profileDir = path.resolve(process.cwd(), options.profile);

  async function launchContext() {
    const stealthArgs = options.stealth ? ["--disable-blink-features=AutomationControlled"] : [];
    const base = {
      headless: options.headless,
      viewport: null,          // null = ブラウザがウィンドウサイズを管理（最大化と組み合わせる）
      args: ["--start-maximized", ...stealthArgs],
      ignoreDefaultArgs: options.stealth ? ["--enable-automation"] : [],
    };
    if (options.channel) {
      return chromium.launchPersistentContext(profileDir, { ...base, channel: options.channel });
    }
    try {
      return await chromium.launchPersistentContext(profileDir, base);
    } catch (e) {
      if (!String(e?.message || e).includes("Executable doesn't exist")) throw e;
      console.warn("[WARN] Playwrightブラウザ未導入。システムChromeへフォールバックします。");
      return chromium.launchPersistentContext(profileDir, { ...base, channel: "chrome" });
    }
  }

  const context = await launchContext();
  let hasFatalError = false;

  try {
    if (options.stealth) {
      await context.addInitScript(() => {
        Object.defineProperty(navigator, "webdriver", { get: () => undefined });
      });
    }

    const page = context.pages()[0] || (await context.newPage());
    await page.goto(options.url, { waitUntil: "domcontentloaded", timeout: 120000 });

    console.log("[INFO] チャートが表示されたらアラートパネル（ベルアイコン）を開き、");
    console.log("       アラート一覧が見える状態にしてから Enter を押してください。");
    await waitForEnter("準備ができたら Enter...");

    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

    // ===== アラートリスト操作（他スクリプトと共通） =====

    async function scrollListToIndex(index) {
      return page.evaluate(({ listXPath, itemIndex, rowHeight }) => {
        const evalXPath = (xpath) => {
          try {
            return document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
          } catch (_) { return null; }
        };
        const list = evalXPath(listXPath);
        if (!list) return { ok: false, reason: "list container not found" };
        const targetTop = Math.max(0, (itemIndex - 1) * rowHeight - rowHeight * 2);
        list.scrollTop = targetTop;
        return { ok: true, targetTop };
      }, { listXPath: LIST_CONTAINER_XPATH, itemIndex: index, rowHeight: ESTIMATED_ROW_HEIGHT });
    }

    async function openEditByXPath(itemXPath, index, dryRun) {
      await scrollListToIndex(index);
      await sleep(250);

      const row = page.locator(`xpath=${itemXPath}`).first();
      if (await row.count() === 0) return { ok: false, reason: "row not found", rowTicker: "" };

      await row.hover({ timeout: 3000 }).catch(() => {});
      await sleep(200);

      const rowTicker = ((await row.locator("[data-name='alert-item-ticker']").first().textContent().catch(() => "")) || "")
        .replace(/\s+/g, " ").trim();

      const box = await row.boundingBox();
      if (!box) return { ok: false, reason: "row not visible", rowTicker };

      const hoverY = box.y + Math.max(6, box.height / 2);
      const edit = row.locator("[data-name='alert-edit-button']").first();
      let visible = await edit.isVisible().catch(() => false);

      if (!visible) {
        for (const xFrac of [0.92, 0.80, 0.70, 0.60]) {
          await page.mouse.move(box.x + box.width * xFrac, hoverY);
          await sleep(200);
          visible = await edit.isVisible().catch(() => false);
          if (visible) break;
        }
      }
      if (!visible) {
        await page.mouse.move(box.x + box.width / 2, box.y - 20);
        await sleep(150);
        await row.hover({ timeout: 2000 }).catch(() => {});
        await sleep(300);
        visible = await edit.isVisible().catch(() => false);
      }
      if (!visible) return { ok: false, reason: "edit button not visible", rowTicker };

      if (!dryRun) await edit.click({ timeout: 3000 });
      return { ok: true, reason: "ok", rowTicker };
    }

    async function getPrimaryDialog() {
      const selectors = [
        "[role='dialog']",
        "[data-name='alert-create-edit-dialog']",
        "[data-name*='alert-edit']",
        "[data-name*='alert-dialog']",
        "[class*='dialog']",
        "[class*='Dialog']",
        "[class*='modal']",
        "[class*='Modal']",
      ];
      for (const sel of selectors) {
        const loc = page.locator(sel);
        const count = await loc.count().catch(() => 0);
        for (let i = count - 1; i >= 0; i--) {
          const el = loc.nth(i);
          if (await el.isVisible().catch(() => false)) return el;
        }
      }
      const containers = page.locator("[class*='popup'], [class*='flyout'], [class*='panel'], [class*='overlay']");
      const cnt = await containers.count().catch(() => 0);
      for (let i = cnt - 1; i >= 0; i--) {
        const c = containers.nth(i);
        if (!(await c.isVisible().catch(() => false))) continue;
        const hasSave = await c.locator("button").filter({ hasText: /保存|更新|作成|Save|Update/i }).count().catch(() => 0);
        if (hasSave > 0) return c;
      }
      console.warn("    [WARN] dialog not found by standard selectors; using full page scope");
      return page.locator("body");
    }

    async function clickDialogSave() {
      const dialog = await getPrimaryDialog();
      const selectorCandidates = [
        "[data-name='save-button']", "[data-name='submit-button']", "[data-name='confirm-button']",
        "[data-name*='save']", "[data-name*='submit']", "[data-name*='confirm']",
      ];
      for (const sel of selectorCandidates) {
        const btn = dialog.locator(sel).first();
        if ((await btn.count().catch(() => 0)) > 0 && (await btn.isVisible().catch(() => false))) {
          const label = (await btn.innerText().catch(() => "")) || sel;
          await btn.click({ timeout: 2000 }).catch(() => {});
          return { clicked: true, label: label.trim() || sel };
        }
      }
      const textCandidates = [/保存/, /更新/, /作成/, /適用/, /^OK$/i, /Save/i, /Update/i, /Apply/i, /Confirm/i];
      const buttons = dialog.locator("button, [role='button']");
      const count = await buttons.count().catch(() => 0);
      for (let i = 0; i < Math.min(count, 40); i++) {
        const b = buttons.nth(i);
        if (!(await b.isVisible().catch(() => false))) continue;
        const text = ((await b.innerText().catch(() => "")) || "").replace(/\s+/g, " ").trim();
        if (text && textCandidates.some((re) => re.test(text))) {
          await b.click({ timeout: 2000 }).catch(() => {});
          return { clicked: true, label: text };
        }
      }
      await page.keyboard.press("Enter").catch(() => {});
      return { clicked: true, label: "Enter(fallback)" };
    }

    // ===== 条件変更ヘルパー =====

    /**
     * ダイアログ内に表示されている可視テキストをダンプする（デバッグ用）
     * not-found 時に自動的に呼ばれる
     */
    async function inspectConditionDialog() {
      const dump = await page.evaluate(() => {
        const isVisible = (el) => {
          if (!el || !el.isConnected) return false;
          const st = window.getComputedStyle(el);
          if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity) < 0.1) return false;
          const rc = el.getBoundingClientRect();
          return rc.width > 0 && rc.height > 0;
        };
        // 短いテキストを持つ葉要素を収集（条件セレクター周辺の手がかりに）
        const results = [];
        for (const el of Array.from(document.querySelectorAll("span, div, button, a, p"))) {
          if (el.children.length > 2) continue;
          if (!isVisible(el)) continue;
          const text = (el.innerText || "").replace(/\s+/g, " ").trim();
          if (!text || text.length > 80 || text.length < 2) continue;
          const rc = el.getBoundingClientRect();
          results.push(`[${Math.round(rc.x)},${Math.round(rc.y)}] <${el.tagName.toLowerCase()}> "${text}"`);
          if (results.length >= 40) break;
        }
        return results;
      });
      console.log("    [Inspect] ダイアログ内可視テキスト（上位40件）:");
      dump.forEach((line) => console.log(`      ${line}`));
    }

    /**
     * ダイアログ内の条件ドロップダウンボタンを探してクリック座標を返す。
     *
     * HTML実測より:
     *   <span data-qa-id="ui-kit-disclosure-control main-series-select"
     *         data-role="listbox" aria-haspopup="listbox" role="button">
     *     <div data-qa-id="item-title">...</div>   ← 現バージョンは表示されない
     *   </span>
     *
     * ダイアログ内のボタン自体にはバージョン情報が無いため、
     * ここではボタン座標を返すのみ。バージョン判定はポップアップ内で行う。
     *
     * 戻り値:
     *   { status: "found", x, y, method }   ボタン発見
     *   { status: "not-found" }              見つからない
     */
    async function findConditionDropdown() {
      return page.evaluate(() => {
        const isVisible = (el) => {
          if (!el || !el.isConnected) return false;
          const st = window.getComputedStyle(el);
          if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity) < 0.1) return false;
          const rc = el.getBoundingClientRect();
          return rc.width > 0 && rc.height > 0;
        };
        const coords = (el) => {
          const rc = el.getBoundingClientRect();
          return { x: rc.x + rc.width / 2, y: rc.y + rc.height / 2 };
        };

        // 1. 最も安定: data-qa-id の値に "main-series-select" が含まれるボタン
        const qaBtn = document.querySelector("[data-qa-id*='main-series-select']");
        if (qaBtn && isVisible(qaBtn)) {
          return { status: "found", ...coords(qaBtn), method: "data-qa-id*=main-series-select" };
        }

        // 2. data-role="listbox" を持つ span[role="button"]（HTML実測パターン）
        for (const el of Array.from(document.querySelectorAll("[data-role='listbox']")).filter(isVisible)) {
          if ((el.getAttribute("role") || "").toLowerCase() === "button") {
            return { status: "found", ...coords(el), method: "data-role=listbox+role=button" };
          }
        }

        // 3. aria-haspopup="listbox" を持つ button 相当要素
        for (const el of Array.from(document.querySelectorAll("[aria-haspopup='listbox']")).filter(isVisible)) {
          if (el.getBoundingClientRect().width > 50) {
            return { status: "found", ...coords(el), method: "aria-haspopup=listbox" };
          }
        }

        // 4. [data-qa-id="item-title"] を含む親ボタンを探す（ダイアログの条件表示エリア）
        const itemTitle = document.querySelector("[data-qa-id='item-title']");
        if (itemTitle && isVisible(itemTitle)) {
          let cur = itemTitle.parentElement;
          while (cur && cur.tagName !== "BODY") {
            const role = (cur.getAttribute("role") || "").toLowerCase();
            if (cur.tagName === "BUTTON" || role === "button") {
              const rc = cur.getBoundingClientRect();
              if (rc.width > 30) return { status: "found", ...coords(cur), method: "item-title-parent" };
            }
            cur = cur.parentElement;
          }
        }

        return { status: "not-found" };
      });
    }

    /**
     * ドロップダウンが開いた後、ポップアップリストから targetVersion を選択する。
     * data-qa-id・role='option'・テキスト含有の3段階で検索。
     */
    async function selectVersionFromPopup(targetVersion, timeoutMs = 3000) {
      const started = Date.now();
      while (Date.now() - started < timeoutMs) {
        const result = await page.evaluate(({ ver }) => {
          const isVisible = (el) => {
            if (!el || !el.isConnected) return false;
            const st = window.getComputedStyle(el);
            if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity) < 0.1) return false;
            const rc = el.getBoundingClientRect();
            return rc.width > 0 && rc.height > 0;
          };
          const doClick = (el) => {
            el.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
            el.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
            el.click();
          };
          const getContainer = (el) =>
            el.closest("[role='option']") || el.closest("[role='menuitem']") ||
            el.closest("[role='listitem']") || el.closest("li") ||
            el.closest("[class*='item']") || el.closest("[class*='row']") ||
            el.parentElement || el;

          // 1. data-qa-id
          for (const el of Array.from(document.querySelectorAll("[data-qa-id='main-series-select-additional-info']")).filter(isVisible)) {
            if ((el.innerText || el.textContent || "").trim() === ver) {
              doClick(getContainer(el));
              return { ok: true, matched: ver, method: "data-qa-id" };
            }
          }

          // 2. option/menuitem/li のテキストが ver を含む
          for (const sel of ["[role='option']", "[role='menuitem']", "[role='listitem']", "li"]) {
            for (const el of Array.from(document.querySelectorAll(sel)).filter(isVisible)) {
              const text = (el.innerText || el.textContent || "").trim();
              if (text === ver || text.includes(ver)) {
                doClick(el);
                return { ok: true, matched: text.slice(0, 80), method: sel };
              }
            }
          }

          // 3. 葉要素のテキストに ver を含む（"Kabuto v7.0" 等）
          for (const tag of ["span", "div", "p", "td", "button", "a"]) {
            for (const el of Array.from(document.querySelectorAll(tag)).filter(isVisible)) {
              if (el.children.length > 4) continue;
              const text = (el.innerText || "").trim();
              if (!text.includes(ver) || text.length > 150) continue;
              doClick(getContainer(el));
              return { ok: true, matched: text.slice(0, 80), method: `text-contains(${tag})` };
            }
          }

          return { ok: false };
        }, { ver: targetVersion });

        if (result.ok) return result;
        await sleep(80);
      }
      return { ok: false };
    }

    /**
     * 条件を fromVersion → toVersion に変更するメイン処理。
     * ダイアログのボタン自体にはバージョンが表示されないため、
     * ポップアップを開いた後にバージョン確認・選択を行う。
     */
    async function changeAlertCondition(fromVersion, toVersion) {
      // 1. 条件ドロップダウンボタンを探す
      const found = await findConditionDropdown();
      console.log(`    [Cond] button: status=${found.status}` +
        (found.method ? ` method=${found.method}` : ""));

      if (found.status === "not-found") {
        await inspectConditionDialog();
        return { ok: false, reason: "条件ドロップダウンボタンが見つかりません" };
      }

      // 2. ドロップダウンを開く
      console.log(`    [Cond] opening dropdown at (${Math.round(found.x)}, ${Math.round(found.y)})`);
      await page.mouse.click(found.x, found.y);
      await sleep(600);

      // 3. ポップアップ内で現在選択中のバージョンを確認
      const currentVersion = await page.evaluate(({ from, to }) => {
        const isVisible = (el) => {
          if (!el || !el.isConnected) return false;
          const st = window.getComputedStyle(el);
          if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity) < 0.1) return false;
          const rc = el.getBoundingClientRect();
          return rc.width > 0 && rc.height > 0;
        };
        // aria-selected="true" の項目のバージョン文字列を取得
        for (const el of Array.from(document.querySelectorAll("[aria-selected='true']")).filter(isVisible)) {
          const verEl = el.querySelector("[data-qa-id='main-series-select-additional-info']");
          if (verEl) return (verEl.innerText || verEl.textContent || "").trim();
        }
        // fallback: data-qa-id="main-series-select-additional-info" の最初の可視要素
        const firstVer = Array.from(document.querySelectorAll("[data-qa-id='main-series-select-additional-info']")).find(isVisible);
        return firstVer ? (firstVer.innerText || firstVer.textContent || "").trim() : "";
      }, { from: fromVersion, to: toVersion });

      if (currentVersion === toVersion) {
        // 既に toVersion が選択されている → ポップアップを閉じてそのまま保存
        console.log(`    [Cond] 既に "${toVersion}" — 変更不要（そのまま保存）`);
        await page.keyboard.press("Escape").catch(() => {});
        await sleep(200);
        return { ok: true, alreadyCorrect: true };
      }

      console.log(`    [Cond] current="${currentVersion || "(unknown)"}" → selecting "${toVersion}"`);

      // 4. ポップアップから toVersion を選択
      const selected = await selectVersionFromPopup(toVersion, 3000);
      if (!selected.ok) {
        await page.keyboard.press("Escape").catch(() => {});
        await sleep(200);
        return { ok: false, reason: `"${toVersion}" がポップアップに見つかりません` };
      }

      console.log(`    [Cond] selected: "${selected.matched}" (${selected.method})`);
      return { ok: true, alreadyCorrect: false, selected: selected.matched };
    }

    // ===== メインループ =====

    console.log("[START]", {
      dryRun: options.dryRun,
      maxUpdates: options.maxUpdates,
      fromVersion: options.fromVersion,
      toVersion: options.toVersion,
    });

    let updatedCount = 0;
    let detectedCount = 0;

    for (let i = 1; i <= options.maxUpdates; i++) {
      const itemXPath = buildItemXPath(ITEM_XPATH_TEMPLATE, i);
      const openResult = await openEditByXPath(itemXPath, i, options.dryRun);

      if (!openResult.ok) {
        console.log(`[${i}] skip: ${openResult.reason}`);
        continue;
      }

      detectedCount++;
      console.log(`[${i}] opened rowTicker=${openResult.rowTicker || "(unknown)"}`);

      if (!options.dryRun) {
        await sleep(options.modalWaitMs);

        const condResult = await changeAlertCondition(options.fromVersion, options.toVersion);
        if (!condResult.ok) {
          console.warn(`    condition failed: ${condResult.reason}`);
          await page.keyboard.press("Escape").catch(() => {});
          await sleep(300);
          continue;
        }

        const save = await clickDialogSave();
        if (save.clicked) {
          updatedCount++;
          console.log(`    save=${save.label || "(clicked)"}`);
        } else {
          console.warn(`    save failed`);
        }
      }

      await sleep(options.betweenClicksMs);
    }

    console.log("[DONE]", {
      updatedCount,
      detectedCount,
      fromVersion: options.fromVersion,
      toVersion: options.toVersion,
      dryRun: options.dryRun,
    });
    await waitForEnter("ブラウザを閉じるには Enter を押してください...");

  } catch (error) {
    hasFatalError = true;
    console.error("[FATAL]", error);
    if (options.keepOpenOnError) {
      await waitForEnter("エラーで停止しました。画面確認後に Enter で終了...");
    }
  } finally {
    if (!(hasFatalError && options.keepOpenOnError)) {
      await context.close();
    }
  }
})();
