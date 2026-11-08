// Browser integration checks. Run with Playwright installed: node metric/test_viewer.cjs
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');

const prefix = 'results/2026-11-07/0_beginner/00_case/';
const fixtures = {
  'standalone.json': { version: 1, programs: [{ source: 'solo\n', lengths: [4, 1] }] },
  [`${prefix}Python/taskA.json`]: { version: 1, programs: [{ source: 'x < y\n', lengths: [1, 1, 1, 1, 1, 1] }] },
  [`${prefix}C++/taskA.json`]: { version: 1, programs: [{ source: 'plus\n', lengths: [4, 1] }] },
  [`${prefix}C#/taskA.json`]: { version: 1, programs: [{ source: 'old\n', lengths: [3, 1] }] },
  [`${prefix}C#/taskB.json`]: { version: 1, programs: [
    { source: '😀<&>\n', lengths: [1, 1, 1, 1, 1] },
    { source: '', lengths: [] },
    { source: '  z\n\n', lengths: [2, 1, 1, 1] },
    { source: '<img src=x onerror="globalThis.injected=1">\n', lengths: [43, 1] },
  ] },
  [`${prefix}Broken/taskA.json`]: { version: 1, programs: [{ source: 'x', lengths: [2] }] },
};
const index = { version: 1, results: { '2026-11-07': { '0_beginner': { '00_case': {
  Python: 'A', 'C++': 'A', 'C#': 'AB', Broken: 'A', Missing: 'A',
} } } } };
const requests = [];
const server = http.createServer(async (req, res) => {
  requests.push(req.url);
  const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).slice(1);
  if (name === 'metric/views.json') {
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify(index));
  }
  if (Object.hasOwn(fixtures, name)) {
    res.setHeader('Content-Type', 'application/json');
    const send = () => res.end(JSON.stringify(fixtures[name]));
    return name === `${prefix}C#/taskA.json` ? setTimeout(send, 150) : send();
  }
  if (/^metric\/viewer\.(html|js|css)$/.test(name)) {
    try {
      const data = await fs.readFile(path.join(__dirname, path.basename(name)));
      res.setHeader('Content-Type', name.endsWith('.js') ? 'text/javascript' :
        name.endsWith('.css') ? 'text/css' : 'text/html');
      return res.end(data);
    } catch {}
  }
  res.writeHead(404);
  res.end('Not found');
});

async function main() {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.ok((await fetch(`${base}/metric/viewer.html`)).ok, 'shared viewer is missing');
  const browser = await chromium.launch({ headless: true,
    ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}),
  });
  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(5000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const url = new URL('/metric/viewer.html', base);
    url.searchParams.set('view', `${prefix}Python/taskA.json`);
    const response = await page.goto(url.href);
    assert.ok(response.ok(), 'shared viewer is missing');
    await page.locator('#programs .program').waitFor();
    assert.deepEqual(await page.locator('.code').allTextContents(), ['x < y', '']);
    assert.deepEqual(requests.filter(x => new URL(x, base).pathname.endsWith('.json') && x !== '/metric/views.json'),
      [`/${prefix}Python/taskA.json`], 'only the selected data should be loaded');
    assert.equal(await page.locator('#language').inputValue(), 'Python');
    console.log('PASS: deep link loads one view and preserves code and final newline');

    await page.selectOption('#language', 'C++');
    await page.waitForFunction(() => document.querySelector('.code')?.textContent === 'plus');
    assert.ok(requests.some(url => url.includes('/C%2B%2B/')));
    assert.ok(new URL(page.url()).searchParams.get('view').endsWith('C++/taskA.json'));
    console.log('PASS: C++ paths and shareable selection URL');

    await Promise.all([
      page.waitForRequest(req => req.url().includes('/C%23/taskA.json')),
      page.selectOption('#language', 'C#'),
    ]);
    await page.selectOption('#task', 'B');
    await page.waitForFunction(() => document.querySelector('.code')?.textContent === '😀<&>');
    assert.equal(await page.locator('.program').count(), 4);
    assert.equal(await page.locator('.token').first().textContent(), '😀');
    assert.deepEqual(await page.locator('.program').nth(1).locator('.number').allTextContents(), ['1']);
    assert.deepEqual(await page.locator('.program').nth(2).locator('.code').allTextContents(), ['  z', '', '']);
    assert.equal(await page.locator('#programs img').count(), 0);
    assert.equal(await page.evaluate(() => globalThis.injected), undefined);
    await new Promise(resolve => setTimeout(resolve, 200));
    assert.equal(await page.locator('.code').first().textContent(), '😀<&>');
    console.log('PASS: Unicode, empty input, multiple programs, safe text, and switching race');

    await page.selectOption('#language', 'Missing');
    await page.waitForFunction(() => document.querySelector('#message').getAttribute('role') === 'alert');
    assert.equal(await page.locator('.program').count(), 0);
    assert.match(await page.locator('#message').textContent(), /404/);
    await page.selectOption('#language', 'Broken');
    await page.waitForFunction(() => document.querySelector('#message').textContent.includes('Invalid token data'));
    assert.equal(await page.locator('.program').count(), 0);
    await page.selectOption('#language', 'Python');
    await page.waitForFunction(() => document.querySelector('.code')?.textContent === 'x < y');
    console.log('PASS: missing/malformed data errors and recovery');

    await page.setViewportSize({ width: 390, height: 844 });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      'mobile page should not overflow horizontally');
    assert.deepEqual(errors, []);
    console.log('PASS: mobile layout and no JavaScript exceptions');

    await page.goto(`${base}/metric/viewer.html?view=standalone.json`);
    await page.waitForFunction(() => document.querySelector('.code')?.textContent === 'solo');
    assert.ok(await page.locator('#controls').isHidden(), 'standalone view must hide unrelated benchmark selectors');
    console.log('PASS: standalone JSON deep link');
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => server.close());
