// Renders every component preview in docs/design/components/ to PNG, in the
// Studio light and dark themes, the way the design-system artifact shows them.
// Usage (from the repo root): node docs/design/render-previews.mjs [Comp,Comp]
// Output: docs/design/screenshots/ (git-ignored). Needs the Playwright package
// and a Chromium it can find, and network access for Google Fonts.
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch { playwright = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'screenshots');
fs.mkdirSync(out, { recursive: true });

// tokens.json -> CSS custom properties, as the artifact compiles them.
function tokensCss(t) {
  const themes = t.color.themes.map((th) => th.id);
  const val = (tok, th) => (typeof tok.value === 'string' ? tok.value : tok.value[th] ?? tok.value[themes[0]]);
  const block = (sel, th) => `${sel} {\n${[...t.color.tokens, ...(t.shadow?.tokens ?? [])].map((k) => `  --${k.name}: ${val(k, th)};`).join('\n')}\n}`;
  const blocks = [block(`:root, [data-theme="${themes[0]}"]`, themes[0]), ...themes.slice(1).map((th) => block(`[data-theme="${th}"]`, th))];
  const flat = Object.entries(t).filter(([k, v]) => !['color', 'type', 'shadow'].includes(k) && v && Array.isArray(v.tokens)).flatMap(([, v]) => v.tokens);
  const families = Object.entries(t.type.families).map(([k, v]) => `  --font-${k}: ${v};`);
  blocks.push(`:root {\n${flat.map((k) => `  --${k.name}: ${k.value};`).join('\n')}\n${families.join('\n')}\n}`);
  return blocks.join('\n');
}

const tokens = tokensCss(JSON.parse(fs.readFileSync(path.join(here, 'tokens.json'), 'utf8')));
const bundle = fs.readFileSync(path.join(here, 'components/bundle.css'), 'utf8');
const all = fs.readdirSync(path.join(here, 'components')).filter((d) => fs.existsSync(path.join(here, 'components', d, 'preview.html')));
const only = process.argv[2] ? process.argv[2].split(',') : all;

const proxy = process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined;
const browser = await playwright.chromium.launch({ proxy, args: proxy ? ['--ignore-certificate-errors'] : [] });
for (const theme of ['light', 'dark']) {
  for (const c of only) {
    const page = await browser.newPage({ viewport: { width: 960, height: 400 }, ignoreHTTPSErrors: true });
    page.on('pageerror', (e) => console.log(`[${c} ${theme}] ${e.message}`));
    let html = fs.readFileSync(path.join(here, 'components', c, 'preview.html'), 'utf8');
    const height = Number(/height=(\d+)/.exec(html)?.[1] ?? 200);
    html = html.replace('<html>', `<html data-theme="${theme}">`).replace('</head>', `<style>${tokens}</style><style>${bundle}</style></head>`);
    await page.setViewportSize({ width: 960, height });
    await page.setContent(html, { waitUntil: 'networkidle' });
    // Animated previews need time to reach a representative frame.
    const wait = { Prompter: 4200, Countdown: 1500, AutoZoom: 3600, CaptionStyles: 2600, CursorCompanion: 2500, DirectorsCut: 4200, RecordScreen: 5600, GlyphMotion: 1500, MarkedScript: 2400 };
    await page.waitForTimeout(wait[c] ?? 800);
    await page.screenshot({ path: path.join(out, `${c}-${theme}.png`) });
    await page.close();
  }
}
await browser.close();
console.log(`Rendered ${only.length * 2} previews to ${path.relative(process.cwd(), out)}/`);
