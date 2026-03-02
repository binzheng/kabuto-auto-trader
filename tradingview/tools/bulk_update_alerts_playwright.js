#!/usr/bin/env node

const path = require("path");
const readline = require("readline");

const ITEM_XPATH_TEMPLATE = "//*[@id='id_alert-widget-tabs-slots_tabpanel_list']/div[2]/div[2]/div/div[{index}]";
const LIST_CONTAINER_XPATH = "//*[@id='id_alert-widget-tabs-slots_tabpanel_list']/div[2]/div[2]/div";
const ESTIMATED_ROW_HEIGHT = 55;

function parseArgs(argv) {
  const args = {
    dryRun: false,
    maxUpdates: 20,
    betweenClicksMs: 900,
    modalWaitMs: 1200,
    url: "https://jp.tradingview.com/chart/2TEyPaCa/?symbol=TSE%3A9984",
    headless: false,
    profile: ".tv-playwright-profile",
    channel: "",
    stealth: true,
    keepOpenOnError: true,
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
  }

  return args;
}

function waitForEnter(message) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(`${message}\n`, () => {
      rl.close();
      resolve();
    });
  });
}

function buildItemXPath(template, index) {
  return template.includes("{index}") ? template.replaceAll("{index}", String(index)) : template.replace(/\[\d+\]$/, `[${index}]`);
}

(async () => {
  const options = parseArgs(process.argv.slice(2));

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
      viewport: null,
      ignoreDefaultArgs: options.stealth ? ["--enable-automation"] : [],
      args: options.stealth
        ? ["--disable-blink-features=AutomationControlled", "--start-maximized"]
        : ["--start-maximized"],
    };

    if (options.channel) return chromium.launchPersistentContext(profileDir, { ...base, channel: options.channel });

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

    async function scrollListToIndex(index) {
      return page.evaluate(({ listXPath, itemIndex, rowHeight }) => {
        const evalXPath = (xpath) => {
          try {
            return document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
          } catch (_) {
            return null;
          }
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
      const rowCount = await row.count();
      if (rowCount === 0) return { ok: false, reason: "row not found", rowTicker: "" };

      // Playwright組み込みのhoverで確実にスクロールしてからhover
      await row.hover({ timeout: 3000 }).catch(() => {});
      await sleep(200);

      const rowTicker = ((await row.locator("[data-name='alert-item-ticker']").first().textContent().catch(() => "")) || "")
        .replace(/\s+/g, " ")
        .trim();

      const box = await row.boundingBox();
      if (!box) return { ok: false, reason: "row not visible", rowTicker };

      const hoverY = box.y + Math.max(6, box.height / 2);
      const edit = row.locator("[data-name='alert-edit-button']").first();
      let visible = await edit.isVisible().catch(() => false);

      // 複数のX座標でhoverを試みる（編集ボタンはhover時のみ表示）
      if (!visible) {
        for (const xFrac of [0.92, 0.80, 0.70, 0.60]) {
          const hoverX = box.x + box.width * xFrac;
          await page.mouse.move(hoverX, hoverY);
          await sleep(200);
          visible = await edit.isVisible().catch(() => false);
          if (visible) break;
        }
      }

      // 最終手段: マウスを一度離してから再hover
      if (!visible) {
        await page.mouse.move(box.x + box.width / 2, box.y - 20);
        await sleep(150);
        await row.hover({ timeout: 2000 }).catch(() => {});
        await sleep(300);
        visible = await edit.isVisible().catch(() => false);
      }

      if (!visible) return { ok: false, reason: "edit button not visible", rowTicker };

      if (!dryRun) {
        await edit.click({ timeout: 3000 });
      }

      return { ok: true, reason: "ok", rowTicker };
    }

    async function getDialogTicker() {
      return page.evaluate(() => {
        const isVisible = (el) => {
          if (!el || !el.isConnected) return false;
          const st = window.getComputedStyle(el);
          if (st.display === "none" || st.visibility === "hidden" || st.opacity === "0") return false;
          const rc = el.getBoundingClientRect();
          return rc.width > 0 && rc.height > 0;
        };

        const dialogs = [
          ...Array.from(document.querySelectorAll("[role='dialog']")),
          ...Array.from(document.querySelectorAll("[data-name*='dialog']")),
          ...Array.from(document.querySelectorAll("[class*='dialog']")),
          ...Array.from(document.querySelectorAll("[class*='modal']")),
        ].filter(isVisible);

        if (!dialogs.length) return { found: false, ticker: "", reason: "dialog not found" };

        const root = dialogs[0];
        const direct = root.querySelector("[data-name*='ticker'], [data-name*='symbol']");
        if (direct) {
          const text = ((direct.value || "") + " " + (direct.textContent || "")).replace(/\s+/g, " ").trim();
          if (text) return { found: true, ticker: text, reason: "direct selector" };
        }

        const textPool = (root.innerText || root.textContent || "").replace(/\s+/g, " ");
        const m = textPool.match(/\b\d{4,5}\b/);
        if (m) return { found: true, ticker: m[0], reason: "regex" };

        return { found: false, ticker: "", reason: "ticker not found in dialog" };
      });
    }

    async function getPrimaryDialog() {
      // TradingViewはハッシュクラス名を使うため複数の方法で探す
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

      // フォールバック: 保存ボタンを持つ可視コンテナを探す
      const containers = page.locator("[class*='popup'], [class*='flyout'], [class*='panel'], [class*='overlay']");
      const cnt = await containers.count().catch(() => 0);
      for (let i = cnt - 1; i >= 0; i--) {
        const c = containers.nth(i);
        if (!(await c.isVisible().catch(() => false))) continue;
        const hasSave = await c.locator("button").filter({ hasText: /保存|更新|作成|Save|Update/i }).count().catch(() => 0);
        if (hasSave > 0) return c;
      }

      // 最終手段: ページ全体をスコープとして返す（ダイアログが非標準構造の場合）
      console.warn("    [WARN] dialog not found by standard selectors; using full page scope");
      return page.locator("body");
    }

    async function trySelectExactTimeframeFromPopup(timeoutMs = 2000) {
      const started = Date.now();
      while (Date.now() - started < timeoutMs) {
        const result = await page.evaluate(() => {
          const normalize = (s) => (s || "").replace(/\s+/g, "").trim().toLowerCase();
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

          // 1. div[class*='title-'] で "5 分" を探してクリック
          for (const el of Array.from(document.querySelectorAll("div[class*='title-']"))) {
            const t = normalize(el.innerText);
            if ((t !== "5分" && t !== "5m" && t !== "5") || !isVisible(el)) continue;
            const clickable = el.closest("[role='option']") || el.closest("[role='menuitem']") || el.closest("li") || el.parentElement || el;
            doClick(clickable);
            return { ok: true, matched: (el.innerText || "").trim(), method: "title-div" };
          }

          // 2. [role='option'] や [role='menuitem'] の innerText から直接探す
          for (const sel of ["[role='option']", "[role='menuitem']", "li"]) {
            for (const el of Array.from(document.querySelectorAll(sel))) {
              const t = normalize(el.innerText);
              if ((t !== "5分" && t !== "5m" && t !== "5") || !isVisible(el)) continue;
              doClick(el);
              return { ok: true, matched: (el.innerText || "").trim(), method: sel };
            }
          }

          return { ok: false, matched: "", method: "" };
        });

        if (result.ok) {
          return { ok: true, matched: result.matched };
        }
        await sleep(80);
      }
      return { ok: false, matched: "" };
    }

    // "1分" など時間足テキストを表示している要素を page.evaluate で幅広く探し、
    // マウス座標クリックでドロップダウンを開いて "5分" を選択する
    async function findAndClickTimeframeDropdown() {
      const TF_NORM = ["1分","2分","3分","4分","6分","10分","15分","20分","30分","45分",
                       "1時間","2時間","3時間","4時間","6時間","8時間","12時間",
                       "1m","2m","3m","4m","5m","6m","10m","15m","20m","30m","45m",
                       "1h","2h","3h","4h","6h","8h","12h","1d","1w","1mo"];

      const hit = await page.evaluate((tfList) => {
        const norm = (s) => (s || "").replace(/\s+/g, "").toLowerCase();
        const isVisible = (el) => {
          if (!el || !el.isConnected) return null;
          const st = window.getComputedStyle(el);
          if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity) < 0.1) return null;
          const rc = el.getBoundingClientRect();
          return (rc.width > 0 && rc.height > 0) ? rc : null;
        };

        // 子要素が少ない葉に近い要素を対象にして時間足テキストを探す
        const all = document.querySelectorAll("span, div, button, a, li, td, p");
        for (const el of all) {
          if (el.children.length > 3) continue;
          const t = norm(el.innerText || el.textContent);
          if (!tfList.includes(t)) continue;
          const rc = isVisible(el);
          if (!rc) continue;
          return { x: rc.x + rc.width / 2, y: rc.y + rc.height / 2, text: (el.innerText || "").trim() };
        }
        return null;
      }, TF_NORM);

      if (!hit) return { ok: false, openerText: "", selectedText: "" };

      // 既に目標の時間足（5分/5m）であればクリック不要
      const normHit = (hit.text || "").replace(/\s+/g, "").toLowerCase();
      if (normHit === "5分" || normHit === "5m") {
        console.log(`    [TF] 時間足は既に "5分" — 変更不要（そのまま保存）`);
        return { ok: true, openerText: hit.text, selectedText: hit.text };
      }

      console.log(`    [TF] 時間足要素発見: "${hit.text}" (${Math.round(hit.x)}, ${Math.round(hit.y)}) → マウスクリック`);
      await page.mouse.click(hit.x, hit.y);
      await sleep(400);

      const selected = await trySelectExactTimeframeFromPopup(2500);
      if (selected.ok) {
        return { ok: true, openerText: hit.text, selectedText: selected.matched };
      }

      await page.keyboard.press("Escape").catch(() => {});
      await sleep(100);
      return { ok: false, openerText: hit.text, selectedText: "" };
    }

    async function setExpirationOneMonth() {
      const dialog = await getPrimaryDialog();
      const scoped = dialog || page.locator("body");

      let dropdown = scoped.locator("[data-qa-id='expiration-time-dropdown-button']").first();
      let found = (await dropdown.count().catch(() => 0)) > 0 && (await dropdown.isVisible().catch(() => false));

      if (!found) {
        dropdown = page.locator("[data-qa-id='expiration-time-dropdown-button']").first();
        found = (await dropdown.count().catch(() => 0)) > 0 && (await dropdown.isVisible().catch(() => false));
      }

      if (!found) {
        const byId = page.locator("button[id][aria-controls]");
        const count = await byId.count().catch(() => 0);
        for (let i = 0; i < Math.min(count, 50); i += 1) {
          const b = byId.nth(i);
          if (!(await b.isVisible().catch(() => false))) continue;
          const txt = ((await b.innerText().catch(() => "")) || "").replace(/\s+/g, " ").trim();
          if (/\d{4}年\d{1,2}月\d{1,2}日/.test(txt)) {
            dropdown = b;
            found = true;
            break;
          }
        }
      }

      if (!found) return { ok: false, reason: "expiration dropdown not found" };

      await dropdown.click({ timeout: 2000 }).catch(() => {});
      await sleep(200);

      // 1) もっとも確実: 表示テキスト "1ヶ月間" を持つ title-* 要素を直接クリック
      const picked = await page.evaluate(() => {
        const norm = (s) => (s || "").replace(/\s+/g, "").trim();
        const isVisible = (el) => {
          if (!el || !el.isConnected) return false;
          const st = window.getComputedStyle(el);
          if (st.display === "none" || st.visibility === "hidden" || parseFloat(st.opacity || "1") < 0.1) return false;
          const rc = el.getBoundingClientRect();
          return rc.width > 0 && rc.height > 0;
        };
        const clickEl = (el) => {
          el.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
          el.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
          el.click();
        };

        const candidates = [
          ...Array.from(document.querySelectorAll("div[class*='title-']")),
          ...Array.from(document.querySelectorAll("[role='option']")),
          ...Array.from(document.querySelectorAll("[role='menuitem']")),
          ...Array.from(document.querySelectorAll("li")),
        ];

        for (const el of candidates) {
          if (!isVisible(el)) continue;
          const t = norm(el.innerText || el.textContent || "");
          if (t !== "1ヶ月間") continue;
          const clickable = el.closest("[role='option']") || el.closest("[role='menuitem']") || el.closest("li") || el;
          clickEl(clickable);
          return { ok: true, text: (el.innerText || "").trim(), method: "direct-title" };
        }
        return { ok: false, text: "", method: "" };
      });

      if (picked.ok) return { ok: true, reason: picked.method, selectedText: picked.text || "1ヶ月間" };

      // 2) Playwright locator fallback
      const option = page
        .locator("div[class*='title-'], [role='option'], [role='menuitem'], li")
        .filter({ hasText: "1ヶ月間" })
        .first();
      if ((await option.count().catch(() => 0)) > 0 && (await option.isVisible().catch(() => false))) {
        await option.click({ timeout: 2000 }).catch(() => {});
        return { ok: true, reason: "locator", selectedText: "1ヶ月間" };
      }

      // 3) 最後のフォールバック
      await page.keyboard.type("1ヶ月間").catch(() => {});
      await sleep(100);
      await page.keyboard.press("Enter").catch(() => {});
      await page.keyboard.press("Escape").catch(() => {});
      return { ok: true, reason: "fallback-enter", selectedText: "1ヶ月間" };
    }

    async function updateDialogConditionAndTimeframe(currentRowTicker = "") {
      let tf;
      if ((currentRowTicker || "").includes("5分")) {
        tf = { ok: true, openerText: "already-5m", selectedText: "5分" };
      } else {
        tf = await findAndClickTimeframeDropdown();
        if (!tf.ok) return { ok: false, reason: "timeframe(5m) option not found" };
      }

      const exp = await setExpirationOneMonth();
      if (!exp.ok) return { ok: false, reason: `expiration update failed: ${exp.reason}` };

      return {
        ok: true,
        reason: "ok",
        conditionFrom: "(skip)",
        conditionTo: "(skip)",
        timeframeFrom: tf.openerText || "(auto)",
        timeframeTo: tf.selectedText,
        expirationTo: exp.selectedText || "1ヶ月間",
      };
    }

    async function clickDialogSave() {
      const dialog = await getPrimaryDialog();
      if (!dialog) {
        const globalButtons = page.locator("button, [role='button']");
        const globalCount = await globalButtons.count().catch(() => 0);
        const globalPatterns = [/保存/, /更新/, /作成/, /適用/, /^OK$/i, /Save/i, /Update/i, /Apply/i, /Confirm/i];
        for (let i = 0; i < Math.min(globalCount, 60); i += 1) {
          const b = globalButtons.nth(i);
          if (!(await b.isVisible().catch(() => false))) continue;
          const text = ((await b.innerText().catch(() => "")) || "").replace(/\s+/g, " ").trim();
          if (!text) continue;
          if (globalPatterns.some((re) => re.test(text))) {
            await b.click({ timeout: 2000 }).catch(() => {});
            return { clicked: true, reason: "ok(global)", label: text };
          }
        }
        await page.keyboard.press("Enter").catch(() => {});
        return { clicked: true, reason: "fallback-enter(no-dialog)", label: "Enter" };
      }

      const selectorCandidates = [
        "[data-name='save-button']",
        "[data-name='submit-button']",
        "[data-name='confirm-button']",
        "[data-name*='save']",
        "[data-name*='submit']",
        "[data-name*='confirm']",
      ];

      for (const sel of selectorCandidates) {
        const btn = dialog.locator(sel).first();
        if ((await btn.count().catch(() => 0)) > 0 && (await btn.isVisible().catch(() => false))) {
          const label = (await btn.innerText().catch(() => "")) || sel;
          await btn.click({ timeout: 2000 }).catch(() => {});
          return { clicked: true, reason: "ok", label: label.trim() || sel };
        }
      }

      const textCandidates = [/保存/, /更新/, /作成/, /適用/, /^OK$/i, /Save/i, /Update/i, /Apply/i, /Confirm/i];
      const buttons = dialog.locator("button, [role='button']");
      const count = await buttons.count().catch(() => 0);
      for (let i = 0; i < Math.min(count, 40); i += 1) {
        const b = buttons.nth(i);
        if (!(await b.isVisible().catch(() => false))) continue;
        const text = ((await b.innerText().catch(() => "")) || "").replace(/\s+/g, " ").trim();
        if (!text) continue;
        if (textCandidates.some((re) => re.test(text))) {
          await b.click({ timeout: 2000 }).catch(() => {});
          return { clicked: true, reason: "ok", label: text };
        }
      }

      await page.keyboard.press("Enter").catch(() => {});
      return { clicked: true, reason: "fallback-enter(in-dialog)", label: "Enter" };
    }

    console.log("[START]", {
      dryRun: options.dryRun,
      maxUpdates: options.maxUpdates,
      betweenClicksMs: options.betweenClicksMs,
      itemXPathTemplate: ITEM_XPATH_TEMPLATE,
    });

    let updatedCount = 0;
    let detectedCount = 0;

    for (let i = 1; i <= options.maxUpdates; i += 1) {
      const itemXPath = buildItemXPath(ITEM_XPATH_TEMPLATE, i);
      const openResult = await openEditByXPath(itemXPath, i, options.dryRun);

      if (!openResult.ok) {
        console.log(`[${i}] skip: ${openResult.reason}`);
        continue;
      }

      detectedCount += 1;
      console.log(`[${i}] opened rowTicker=${openResult.rowTicker || "(unknown)"}`);

      if (!options.dryRun) {
        await sleep(options.modalWaitMs);

        const dialogTicker = await getDialogTicker();
        console.log(`    dialogTicker=${dialogTicker.ticker || "(not found)"} (${dialogTicker.reason})`);

        const changeResult = await updateDialogConditionAndTimeframe(openResult.rowTicker);
        if (!changeResult.ok) {
          console.warn(`    change failed: ${changeResult.reason}`);
          // ダイアログを閉じてから次へ（開いたままにしない）
          await page.keyboard.press("Escape").catch(() => {});
          await sleep(300);
          continue;
        }
        console.log(`    changed: condition ${changeResult.conditionFrom} -> ${changeResult.conditionTo}, timeframe ${changeResult.timeframeFrom} -> ${changeResult.timeframeTo}, expiration -> ${changeResult.expirationTo || "1ヶ月間"}`);

        const save = await clickDialogSave();
        if (save.clicked) {
          updatedCount += 1;
          console.log(`    save=${save.label || "(clicked)"}`);
        } else {
          console.warn(`    save failed: ${save.reason}`);
        }
      }

      await sleep(options.betweenClicksMs);
    }

    console.log("[DONE]", { updatedCount, detectedCount, dryRun: options.dryRun });
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
