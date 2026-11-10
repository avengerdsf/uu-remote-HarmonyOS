const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');

const root = path.resolve(__dirname, '../..');
const target = path.resolve(root, process.argv[2] || '../tmp/app-icon-20261109');
const sourceNames = ['ohos_ic_public_device_matebook.svg', 'arrow_up_left.svg'];

(async () => {
  await fs.mkdir(target, { recursive: true });
  const sources = await Promise.all(sourceNames.map(name => fs.readFile(path.join(__dirname, 'huawei', name), 'utf8')));
  const inner = text => text.replace(/<\?xml[^>]*>/g, '').replace(/^.*?<svg[^>]*>/s, '').replace(/<\/svg>\s*$/, '')
    .replace(/fill="rgba\([^"]*\)"/g, 'fill="currentColor"');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    <defs>
      <linearGradient id="blue" x1="0" y1="0" x2="0.8" y2="1"><stop stop-color="#268CFF"/><stop offset="0.52" stop-color="#1465EF"/><stop offset="1" stop-color="#2146CF"/></linearGradient>
      <radialGradient id="light" cx="0.12" cy="0" r="0.95"><stop stop-color="#B2EEFF" stop-opacity=".24"/><stop offset="1" stop-color="#B2EEFF" stop-opacity="0"/></radialGradient>
      <linearGradient id="white" x1="0" y1="0" x2="0.3" y2="1"><stop stop-color="#FFF"/><stop offset="1" stop-color="#D9EBFF"/></linearGradient>
      <filter id="shadow" x="-30%" y="-30%" width="160%" height="180%"><feDropShadow dy="14" stdDeviation="15" flood-color="#082873" flood-opacity=".20"/></filter>
    </defs>
    <rect width="1024" height="1024" fill="#1465EF"/>
    <rect width="1024" height="1024" fill="url(#light)"/>
    <g filter="url(#shadow)">
      <g transform="translate(182 172) scale(27.5)" fill="url(#white)">${inner(sources[0])}</g>
      <circle cx="755" cy="672" r="117" fill="#FFF"/>
      <g transform="translate(635 552) scale(10)" color="#175DE2" fill="#175DE2">${inner(sources[1])}</g>
    </g>
  </svg>`;
  await fs.writeFile(path.join(target, 'app_icon.svg'), svg);
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  const foreground = svg.replace(/<rect width="1024" height="1024" fill="#[A-Fa-f0-9]+"\/>/, '');
  const foregroundPng = await sharp(Buffer.from(foreground)).png().toBuffer();
  const backgroundPng = await sharp({ create: { width: 1024, height: 1024, channels: 4, background: '#1465EF' } }).png().toBuffer();
  await fs.writeFile(path.join(target, 'app_icon_foreground.png'), foregroundPng);
  await fs.writeFile(path.join(target, 'app_icon_background.png'), backgroundPng);
  await fs.writeFile(path.join(target, 'app_layered_icon.json'), JSON.stringify({
    'layered-image': { background: '$media:app_icon_background', foreground: '$media:app_icon_foreground' }
  }, null, 2) + '\n');
  const mask = Buffer.from('<svg width="1024" height="1024"><rect width="1024" height="1024" rx="256" fill="white"/></svg>');
  const masked = await sharp(png).composite([{ input: mask, blend: 'dest-in' }]).png().toBuffer();
  await fs.writeFile(path.join(target, 'app_icon.png'), masked);
  const preview = await sharp(masked).resize(256, 256).png().toBuffer();
  await fs.writeFile(path.join(target, 'preview.png'), preview);
  const samples = await Promise.all([96, 64, 48, 32].map(size => sharp(masked).resize(size, size).png().toBuffer()));
  const sheet = sharp({ create: { width: 640, height: 290, channels: 4, background: '#EDF1F7' } });
  await sheet.composite([{ input: preview, left: 18, top: 18 }, ...samples.map((input, i) => ({ input, left: 310 + (i % 2) * 145, top: 44 + Math.floor(i / 2) * 140 }))]).png().toFile(path.join(target, 'sizes.png'));
  const metadata = {
    sources: sourceNames.map((name, index) => ({ file: 'scripts/ui/huawei/' + name, sha256: crypto.createHash('sha256').update(sources[index]).digest('hex') })),
    geometry: 'Original Huawei SVG outlines, uniformly scaled; opaque solid background and transparent foreground; system layered mask',
    size: 1024,
    iconSha256: crypto.createHash('sha256').update(masked).digest('hex'),
    foregroundSha256: crypto.createHash('sha256').update(foregroundPng).digest('hex'),
    backgroundSha256: crypto.createHash('sha256').update(backgroundPng).digest('hex')
  };
  await fs.writeFile(path.join(target, 'source.json'), JSON.stringify(metadata, null, 2) + '\n');
  console.log(JSON.stringify({ target, ...metadata }));
})().catch(error => { console.error(error); process.exitCode = 1; });
