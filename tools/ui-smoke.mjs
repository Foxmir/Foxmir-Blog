import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const rootUrl = process.argv[2] || 'https://foxmir.github.io/Foxmir-Blog/';
const outDir = process.argv[3] || path.join(process.cwd(), 'artifacts', 'ui-smoke');

const pages = [
  { name: 'home', url: rootUrl },
  { name: 'about', url: new URL('about.html', rootUrl).toString() },
  { name: 'life', url: new URL('life.html', rootUrl).toString() },
  { name: 'category', url: new URL('test4folder.html', rootUrl).toString() },
  { name: 'post', url: new URL('publish/Hello_world.html', rootUrl).toString() }
];

async function ensureDir(dir) {
  await fs.promises.mkdir(dir, { recursive: true });
}

async function findThemeToggle(page) {
  const selectors = [
    '.quarto-color-scheme-toggle',
    '[title*="dark" i]',
    '[title*="theme" i]',
    '[aria-label*="dark" i]',
    '[aria-label*="theme" i]'
  ];

  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.count()) {
      return locator;
    }
  }

  return null;
}

async function snapshot(page, filePath) {
  await page.screenshot({ path: filePath, fullPage: true });
}

(async () => {
  await ensureDir(outDir);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1600 } });
  const page = await context.newPage();
  const summary = [];

  for (const entry of pages) {
    await page.goto(entry.url, { waitUntil: 'networkidle', timeout: 120000 });
    await page.emulateMedia({ colorScheme: 'light' });
    await page.waitForTimeout(1200);

    const title = await page.title();
    const navTexts = await page.locator('.navbar a, .navbar .nav-link').allInnerTexts().catch(() => []);
    const lightPath = path.join(outDir, `${entry.name}-light.png`);
    await snapshot(page, lightPath);

    const toggle = await findThemeToggle(page);
    let darkCaptured = false;
    if (toggle) {
      await toggle.click({ force: true });
      await page.waitForTimeout(1200);
      const darkPath = path.join(outDir, `${entry.name}-dark.png`);
      await snapshot(page, darkPath);
      darkCaptured = true;
      await toggle.click({ force: true }).catch(() => {});
      await page.waitForTimeout(400);
    }

    summary.push({
      name: entry.name,
      url: page.url(),
      title,
      navTexts,
      hasToggle: Boolean(toggle),
      darkCaptured
    });
  }

  await fs.promises.writeFile(path.join(outDir, 'summary.json'), JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  await browser.close();
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
