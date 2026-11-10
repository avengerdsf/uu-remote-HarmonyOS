const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../..');
const output = path.resolve(process.argv[2] || path.join(root, '../tmp/terminal-inset'));

(async () => {
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true,
    args: ['--disable-crash-reporter', '--disable-breakpad', '--disk-cache-dir=' + path.join(output, 'browser-cache')] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(pathToFileURL(path.join(root, 'harmony/entry/src/main/resources/rawfile/terminal/index.html')).href);
    await page.evaluate(() => { window.uuSetTopInset(104); window.uuFit(); });
    const measure = () => page.evaluate(() => ({
      top: document.querySelector('.xterm-screen').getBoundingClientRect().top,
      bottom: document.querySelector('.xterm-screen').getBoundingClientRect().bottom,
      height: window.innerHeight,
      rows: term.rows, base: term.buffer.active.baseY, viewport: term.buffer.active.viewportY
    }));
    const initial = await measure();
    assert.equal(initial.top, 104, 'the first row must avoid the header');
    assert.ok(initial.bottom <= initial.height - 80, 'all terminal rows must fit above the controls');
    await page.evaluate(() => new Promise(resolve => {
      term.write(Array.from({ length: 150 }, (_, index) => 'scrollback line ' + index + '\r\n').join(''), resolve);
    }));
    await page.evaluate(() => term.scrollLines(-2));
    await page.waitForTimeout(120);
    const partial = await measure();
    assert.ok(partial.top < initial.top && partial.top > 8, 'scrolling must progressively enter the header');
    await page.evaluate(() => term.scrollLines(-15));
    await page.waitForTimeout(120);
    const scrolled = await measure();
    assert.equal(scrolled.top, 8, 'scrollback must reach the blurred header');
    assert.ok(scrolled.bottom <= scrolled.height - 80, 'expanding the viewport must keep the last row visible');
    await page.screenshot({ path: path.join(output, 'scrollback.png') });
    await page.evaluate(() => term.scrollToBottom());
    await page.waitForTimeout(120);
    const restored = await measure();
    assert.equal(restored.top, 104, 'the live terminal must restore the initial inset');
    assert.ok(restored.bottom <= restored.height - 80, 'restoring the inset must preserve the last row');
    await page.setViewportSize({ width: 844, height: 390 });
    await page.evaluate(() => { window.uuSetTopInset(80); window.uuFit(); });
    await page.waitForTimeout(120);
    assert.equal((await measure()).top, 80, 'rotation must preserve the first-row inset');
    await page.evaluate(() => new Promise(resolve => term.write('\u001b[?1049h', resolve)));
    await page.locator('#terminal').hover();
    await page.mouse.wheel(0, -100);
    await page.waitForTimeout(160);
    assert.equal((await measure()).top, 8, 'alternate-screen scrolling must also enter the header');
    await page.mouse.wheel(0, 100);
    await page.waitForTimeout(160);
    assert.equal((await measure()).top, 80, 'opposite scrolling must restore the alternate-screen inset');
    assert.deepEqual(errors, []);
    const result = { initial, partial, scrolled, restored, errors };
    await fs.writeFile(path.join(output, 'result.json'), JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
