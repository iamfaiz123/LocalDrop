const { chromium } = require('playwright');
const fs = require('fs');
const [,, base, pin, dir] = process.argv;
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ acceptDownloads: true, viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(base + '/?sid=test');
  await page.waitForSelector('#v-join:not([hidden])');
  console.log('join title:', await page.textContent('#joinSession'));
  await page.fill('#joinName', 'Riya');
  await page.fill('#joinPin', '000000');
  await page.click('#joinBtn');
  await page.waitForSelector('#joinError:not([hidden])');
  console.log('wrong pin error:', await page.textContent('#joinError'));
  await page.fill('#joinPin', pin);
  await page.click('#joinBtn');
  await page.waitForSelector('#v-gallery:not([hidden])');
  await page.waitForSelector('#conn:not(.bad)');
  console.log('gallery:', await page.textContent('#galTitle'), '|', await page.textContent('#galSub'));
  await page.screenshot({ path: dir + '/web-empty.png' });

  // Second participant in another context sees live updates.
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const p2 = await ctx2.newPage();
  await p2.goto(base);
  await p2.fill('#joinName', 'Karan');
  await p2.fill('#joinPin', pin);
  await p2.click('#joinBtn');
  await p2.waitForSelector('#v-gallery:not([hidden])');

  await page.setInputFiles('#fileInput', [dir + '/photo0.jpg', dir + '/photo1.jpg', dir + '/photo2.jpg', dir + '/clip.mp4']);
  await page.waitForFunction(() => document.querySelectorAll('#grid .tile').length === 4, null, { timeout: 30000 });
  console.log('uploader grid tiles:', await page.locator('#grid .tile').count());
  await p2.waitForFunction(() => document.querySelectorAll('#grid .tile').length === 4, null, { timeout: 30000 });
  console.log('live update on second participant: 4 tiles');
  // thumbnails: 3 server-generated + 1 client-generated for the video
  await page.waitForFunction(() => document.querySelectorAll('#grid .tile img').length === 4, null, { timeout: 30000 });
  await p2.waitForFunction(() => document.querySelectorAll('#grid .tile img').length === 4, null, { timeout: 30000 });
  console.log('thumbnails visible (incl. client-made video thumbnail)');
  await page.click('#transfersBtn');
  await page.click('#tabDone');
  console.log('completed transfers:', await page.locator('#transferList .item').count());
  await page.screenshot({ path: dir + '/web-transfers.png' });
  await page.click('#sheetBackdrop', { position: { x: 20, y: 20 } });
  await page.screenshot({ path: dir + '/web-gallery.png' });

  // Duplicate upload is detected.
  await page.setInputFiles('#fileInput', [dir + '/photo0.jpg']);
  await page.waitForTimeout(1500);
  console.log('tiles after duplicate:', await page.locator('#grid .tile').count());

  // Viewer: video plays from Range requests.
  await p2.locator('#grid .tile').first().click();
  await p2.waitForSelector('#viewer:not([hidden])');
  const hasVideo = await p2.locator('#vMedia video').count();
  if (hasVideo) {
    await p2.waitForFunction(() => { const v = document.querySelector('#vMedia video'); return v && v.readyState >= 1; }, null, { timeout: 15000 });
    console.log('video metadata loaded, duration', await p2.evaluate(() => document.querySelector('#vMedia video').duration));
  }
  await p2.click('#vNext');
  await p2.waitForFunction(() => { const i = document.querySelector('#vMedia img'); return i && i.complete && i.naturalWidth > 0; }, null, { timeout: 15000 });
  console.log('photo viewer image', await p2.evaluate(() => document.querySelector('#vMedia img').naturalWidth));
  await p2.click('#vFav');
  await p2.screenshot({ path: dir + '/web-viewer.png' });
  await p2.click('#vClose');

  // Select all & download as ZIP.
  await p2.click('#selectBtn');
  await p2.click('#selAll');
  const [download] = await Promise.all([p2.waitForEvent('download'), p2.click('#selDownload')]);
  const zipPath = dir + '/export.zip';
  await download.saveAs(zipPath);
  console.log('zip downloaded:', download.suggestedFilename(), fs.statSync(zipPath).size, 'bytes');

  // Favorites filter.
  await p2.click('[data-kind="fav"]');
  await p2.waitForFunction(() => document.querySelectorAll('#grid .tile').length === 1);
  console.log('favorites filter: 1 tile');

  // Uploader deletes a photo -> disappears for the other participant.
  await page.locator('#grid .tile').nth(1).click();
  page.once('dialog', (d) => d.accept());
  await page.click('#vDelete');
  await page.waitForFunction(() => document.querySelectorAll('#grid .tile').length === 3);
  await p2.click('[data-kind="all"]');
  await p2.waitForFunction(() => document.querySelectorAll('#grid .tile').length === 3, null, { timeout: 10000 });
  console.log('delete propagated: 3 tiles');
  console.log('page errors:', JSON.stringify(errors));
  await browser.close();
})().catch((e) => { console.error('TEST FAILED', e); process.exit(1); });
