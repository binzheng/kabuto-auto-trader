#!/usr/bin/env node
/**
 * TradingView Alert Expiry Bulk Updater (Playwright)
 *
 * 使用方法:
 *   node tradingview/tools/bulk_update_expiry_playwright.js
 *   node tradingview/tools/bulk_update_expiry_playwright.js --expiry=1ヶ月間 --max-updates=20
 *   node tradingview/tools/bulk_update_expiry_playwright.js --dry-run --max-updates=5
 *
 * 主なオプション:
 *   --expiry=<プリセット>         変更後の有効期限プリセット（デフォルト: 1ヶ月間）
 *                                 例: "1ヶ月間", "3ヶ月間", "6ヶ月間", "無期限", "Open-ended"
 *   --dry-run                    クリックせず対象検出のみ
 *   --max-updates=20             最大更新件数
 *   --profile=.tv-playwright-profile  ログインセッション保存先（他スクリプトと共通）
 *   --channel=chrome             システムChromeを使用
 *   --headless                   ヘッドレス実行
 *   --between-clicks-ms=1000     アラート間のインターバル(ms)
 *   --modal-wait-ms=1200         ダイアログ表示待ち(ms)
 *
 * HTML実測より（2026年):
 *   ボタン: <button data-qa-id="expiration-time-dropdown-button">2026年4月19日 20:35</button>
 *   選択肢: <div class="title-fzPHowFJ ...">1ヶ月間</div>
 */

const path = require("path");
const readline = require("readline");

const ITEM_XPATH_TEMPLATE = "//*[@id='id_alert-widget-tabs-slots_tabpanel_list']/div[2]/div[2]/div/div[{index}]";
const LIST_CONTAINER_XPATH = "//*[@id='id_alert-widget-tabs-slots_tabpanel_list']/div[2]/div[2]/div";
const ESTIMATED_ROW_HEIGHT = 55;

// 「特定の日時」に対応するラベル（日本語・英語）
const SPECIFIC_TIME_LABELS = ["特定の日時", "特定の時間", "Specific time", "Open time", "Date & Time"];
// 有効期限セクションのラベル
const EXPIRY_SECTION_LABELS = ["有効期限", "Expiration", "Expiry"];

function parseArgs(argv) {
  const args = {
    dryRun: false,
    maxUpdates: 20,
    betweenClicksMs: 1000,
    modalWaitMs: 1200,
    url: "https://jp.tradingview.com/#alerts",
    headless: false,
    profile: ".tv-playwright-profile",
    channel: "",
    stealth: true,
    keepOpenOnError: true,
    expiry: "",
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
    else if (arg.startsWith("--expiry=")) args.expiry = arg.substring("--expiry=".length);
  }

  return args;
}

/** "YYYY-MM-DD" または "YYYY-MM-DDTHH:mm" を "YYYY-MM-DDTHH:mm" に正規化する */
function normalizeExpiry(expiry) {
  if (!expiry) return null;
  const m = expiry.match(/^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}))?/);
  if (!m) return null;
  return `${m[1]}T${m[2] || "23:59"}`;
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

  const targetDatetime = normalizeExpiry(options.expiry);
  if (!targetDatetime) {
    console.error("[ERROR] --expiry=YYYY-MM-DD が必要です。例: --expiry=2027-01-01");
    console.error("        時刻を指定する場合: --expiry=2027-01-01T23:59");
    process.exit(1);
  }

  console.log(`[INFO] 有効期限を "${targetDatetime}" に一括更新します`);

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
    const base = {
      headless: options.headless,
      viewport: { width: 1500, height: 900 },
      ignoreDefaultArgs: options.stealth ? ["--enable-automation"] : [],
      args: options.stealth ? ["--disable-blink-features=AutomationControlled"] : [],
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

    console.log("[INFO] ログインしてアラート一覧を開いたら Enter を押してください。");
    await waitForEnter("準備ができたら Enter...");

    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

    // ===== アラートリスト操作（タイムフレームスクリプトと共通） =====

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

    // ===== 有効期限変更ヘルパー =====

    /**
     * ダイアログ内の有効期限ドロップダウンを探し、
     * 「特定の日時」を選択する（既に選択済みの場合はスキップ）。
     * 戻り値:
     *   { ok: true, method: "already" | "select" | "custom" }
     *   { ok: false, method: "need-click", x, y }   → マウスクリックが必要
     *   { ok: false, method: "not-found" }           → 有効期限セクション自体が見つからない
     */
    async function selectSpecificTimeExpiry() {
      return page.evaluate(({ sectionLabels, optLabels }) => {
        const norm = (s) => (s || "").replace(/\s+/g, "").toLowerCase();
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

        // 1. ネイティブ <select> で有効期限セクションを探す
        for (const sel of Array.from(document.querySelectorAll("select")).filter(isVisible)) {
          const parent = sel.closest("div, section, label, fieldset") || sel.parentElement;
          if (!parent) continue;
          const parentText = norm(parent.innerText || parent.textContent);
          if (!sectionLabels.some((l) => parentText.includes(norm(l)))) continue;

          // 既に「特定の日時」が選択されているか確認
          const curOpt = sel.options[sel.selectedIndex];
          if (optLabels.some((l) => norm(curOpt?.text || "").includes(norm(l)))) {
            return { ok: true, method: "already", current: curOpt?.text || "" };
          }
          // 「特定の日時」オプションを選択
          for (const opt of Array.from(sel.options)) {
            if (optLabels.some((l) => norm(opt.text).includes(norm(l)))) {
              sel.value = opt.value;
              sel.dispatchEvent(new Event("change", { bubbles: true }));
              return { ok: true, method: "select", selected: opt.text };
            }
          }
        }

        // 2. カスタムドロップダウン（button, combobox 等）を探す
        const CLICKABLE = [
          "button", "[role='button']", "[role='listbox']", "[role='combobox']",
          "[class*='select']", "[class*='dropdown']", "[class*='picker']",
        ].join(", ");
        for (const el of Array.from(document.querySelectorAll(CLICKABLE)).filter(isVisible)) {
          const parent = el.closest("div, section, label") || el.parentElement;
          if (!parent) continue;
          const parentText = norm(parent.innerText || parent.textContent);
          if (!sectionLabels.some((l) => parentText.includes(norm(l)))) continue;

          const elText = norm(
            el.innerText || el.textContent || el.getAttribute("aria-label") || el.getAttribute("title") || ""
          );
          // 既に「特定の日時」が表示されていれば skip
          if (optLabels.some((l) => elText.includes(norm(l)))) {
            return { ok: true, method: "already", current: el.innerText?.trim() || "" };
          }
          // ドロップダウンを開くためクリック座標を返す
          const rc = el.getBoundingClientRect();
          return {
            ok: false, method: "need-click",
            x: rc.x + rc.width / 2, y: rc.y + rc.height / 2,
            currentText: el.innerText?.trim() || "",
          };
        }

        return { ok: false, method: "not-found" };
      }, { sectionLabels: EXPIRY_SECTION_LABELS, optLabels: SPECIFIC_TIME_LABELS });
    }

    /**
     * ドロップダウンが開いた後、ポップアップから「特定の日時」を選択する
     */
    async function selectSpecificTimeFromPopup(timeoutMs = 2000) {
      const started = Date.now();
      while (Date.now() - started < timeoutMs) {
        const result = await page.evaluate(({ labels }) => {
          const norm = (s) => (s || "").replace(/\s+/g, "").toLowerCase();
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

          const scopes = ["[role='option']", "[role='menuitem']", "[role='listitem']", "li",
                          "div[class*='item']", "div[class*='option']", "div[class*='row']"];
          for (const sel of scopes) {
            for (const el of Array.from(document.querySelectorAll(sel)).filter(isVisible)) {
              const t = norm(el.innerText || el.textContent || "");
              if (labels.some((l) => t.includes(norm(l)))) {
                const clickable = el.closest("[role='option']") || el.closest("[role='menuitem']")
                  || el.closest("li") || el;
                doClick(clickable);
                return { ok: true, matched: (el.innerText || "").trim() };
              }
            }
          }
          return { ok: false };
        }, { labels: SPECIFIC_TIME_LABELS });

        if (result.ok) return result;
        await sleep(80);
      }
      return { ok: false };
    }

    /**
     * ダイアログ内の日時入力フィールドに値をセットする。
     * React/Vue の仮想 DOM に対応するため、nativeInputValueSetter を使用。
     * 戻り値:
     *   { ok: true, method, value }
     *   { ok: false, method: "click-needed", x, y }  → クリックして入力が必要
     *   { ok: false, method: "not-found" }
     */
    async function fillExpiryDatetime(targetDt) {
      const dateOnly = targetDt.split("T")[0];
      const timeOnly = targetDt.split("T")[1] || "23:59";

      return page.evaluate(({ dt, dateOnly, timeOnly, sectionLabels }) => {
        const isVisible = (el) => {
          if (!el || !el.isConnected) return false;
          const st = window.getComputedStyle(el);
          if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity) < 0.1) return false;
          const rc = el.getBoundingClientRect();
          return rc.width > 0 && rc.height > 0;
        };

        // React 対応: nativeInputValueSetter でセットしてから input/change イベントを発火
        const fireInputChange = (el, value) => {
          try {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
            if (setter) setter.call(el, value);
            else el.value = value;
          } catch (_) { el.value = value; }
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        };

        // 1. datetime-local 入力
        const dtInputs = Array.from(document.querySelectorAll("input[type='datetime-local']")).filter(isVisible);
        if (dtInputs.length > 0) {
          fireInputChange(dtInputs[0], dt);
          return { ok: true, method: "datetime-local", value: dtInputs[0].value };
        }

        // 2. date + time の2フィールド分割
        const dateInputs = Array.from(document.querySelectorAll("input[type='date']")).filter(isVisible);
        const timeInputs = Array.from(document.querySelectorAll("input[type='time']")).filter(isVisible);
        if (dateInputs.length > 0) {
          fireInputChange(dateInputs[0], dateOnly);
          if (timeInputs.length > 0) fireInputChange(timeInputs[0], timeOnly);
          return { ok: true, method: "date+time", value: `${dateOnly}T${timeOnly}` };
        }

        // 3. 有効期限セクション付近のテキスト入力
        const norm = (s) => (s || "").replace(/\s+/g, " ").toLowerCase();
        const allInputs = Array.from(document.querySelectorAll("input")).filter(isVisible);
        for (const inp of allInputs) {
          const parent = inp.closest("div, section, label, fieldset") || inp.parentElement;
          if (!parent) continue;
          const parentText = norm(parent.innerText || parent.textContent);
          if (sectionLabels.some((l) => parentText.includes(norm(l)))) {
            fireInputChange(inp, dt.replace("T", " "));
            return { ok: true, method: "near-expiry-label", value: inp.value };
          }
        }

        // 4. 日付っぽい既存値 / placeholder を持つ入力を座標で返す（クリック+タイプで対応）
        for (const inp of allInputs) {
          const hint = (inp.value || inp.placeholder || "").toLowerCase();
          if (/\d{4}|年|date|日時|expir/.test(hint)) {
            const rc = inp.getBoundingClientRect();
            return { ok: false, method: "click-needed", x: rc.x + rc.width / 2, y: rc.y + rc.height / 2 };
          }
        }

        return { ok: false, method: "not-found" };
      }, { dt: targetDt, dateOnly, timeOnly, sectionLabels: EXPIRY_SECTION_LABELS });
    }

    /**
     * ダイアログの有効期限を targetDt に変更する
     */
    async function updateAlertExpiry(targetDt) {
      // Step 1: 「特定の日時」タイプを選択
      const selectResult = await selectSpecificTimeExpiry();
      console.log(`    [Expiry] type: method=${selectResult.method}` +
        (selectResult.current ? ` current="${selectResult.current}"` : "") +
        (selectResult.selected ? ` selected="${selectResult.selected}"` : ""));

      if (!selectResult.ok) {
        if (selectResult.method === "need-click") {
          // カスタムドロップダウンを開いてポップアップから選択
          console.log(`    [Expiry] opening dropdown at (${Math.round(selectResult.x)}, ${Math.round(selectResult.y)})`);
          await page.mouse.click(selectResult.x, selectResult.y);
          await sleep(400);
          const fromPopup = await selectSpecificTimeFromPopup(2000);
          if (!fromPopup.ok) {
            await page.keyboard.press("Escape").catch(() => {});
            await sleep(200);
            return { ok: false, reason: "「特定の日時」オプションが見つかりません" };
          }
          console.log(`    [Expiry] popup selected: "${fromPopup.matched}"`);
          await sleep(400);
        } else if (selectResult.method === "not-found") {
          // 有効期限セクション自体が見つからない場合でも日付入力を試みる
          console.warn("    [Expiry] 有効期限セクションが見つかりません。日付直接入力を試みます。");
        } else {
          return { ok: false, reason: `expiry selection failed: ${selectResult.method}` };
        }
      }

      // Step 2: 日時フィールドに値をセット
      await sleep(300); // 日時入力フィールドが表示されるまで待機
      const fillResult = await fillExpiryDatetime(targetDt);
      console.log(`    [Expiry] fill: method=${fillResult.method}` +
        (fillResult.value ? ` value="${fillResult.value}"` : ""));

      if (!fillResult.ok) {
        if (fillResult.method === "click-needed") {
          // クリックしてフォーカス → 全選択 → タイプ
          await page.mouse.click(fillResult.x, fillResult.y);
          await sleep(300);
          await page.keyboard.press("Control+a");
          await page.keyboard.type(targetDt.replace("T", " "), { delay: 30 });
          return { ok: true, reason: "typed", value: targetDt };
        }
        return { ok: false, reason: `日時フィールドへの入力失敗: ${fillResult.method}` };
      }

      return { ok: true, reason: "ok", value: fillResult.value };
    }

    // ===== メインループ =====

    console.log("[START]", {
      dryRun: options.dryRun,
      maxUpdates: options.maxUpdates,
      targetDatetime,
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

        const expiryResult = await updateAlertExpiry(targetDatetime);
        if (!expiryResult.ok) {
          console.warn(`    expiry failed: ${expiryResult.reason}`);
          await page.keyboard.press("Escape").catch(() => {});
          await sleep(300);
          continue;
        }
        console.log(`    expiry set: ${expiryResult.value}`);

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

    console.log("[DONE]", { updatedCount, detectedCount, targetDatetime, dryRun: options.dryRun });
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
