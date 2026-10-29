// Run with Node.js and sharp available (or set NODE_PATH to its package directory).
// The editable SVG is the source; PNG/ICNS are platform exports, not new designs.
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const base = fs.readFileSync(path.join(root, 'Branding/Chordesk.svg'), 'utf8');
const dark = base.replace('<stop stop-color="#f9fafb"/><stop offset="1" stop-color="#e8edf2"/>', '<stop stop-color="#1a232e"/><stop offset="1" stop-color="#030508"/>');
const transparent = base.replace(/  <rect id="background"[^>]+\/>\n/, '')
  .replace('id="chordesk-symbol"', 'id="chordesk-symbol" opacity="0.9"');
async function main() {
  for (const [suffix, source] of [['dark',dark],['transparent',transparent]]) {
    fs.writeFileSync(path.join(root, `Branding/Chordesk-${suffix}.svg`), source);
    await sharp(Buffer.from(source)).png().toFile(path.join(root, `Branding/Chordesk-${suffix}.png`));
  }
  await sharp(Buffer.from(dark)).flatten({background:'#030508'}).png()
    .toFile(path.join(root, 'iPhoneDuoDemo/Assets.xcassets/AppIcon.appiconset/Chordesk.png'));
  fs.copyFileSync(path.join(root, 'Branding/Chordesk-transparent.png'), path.join(root, 'iPhoneDuoDemo/Resources/Brand/Chordesk.png'));
  const directory = fs.mkdtempSync('/private/tmp/chordesk-icon-');
  const iconset = path.join(directory, 'Chordesk.iconset');fs.mkdirSync(iconset);
  for (const size of [16,32,128,256,512]) {
    for (const scale of [1,2]) {
      await sharp(Buffer.from(dark)).resize(size*scale,size*scale).png()
        .toFile(path.join(iconset,`icon_${size}x${size}${scale===2?'@2x':''}.png`));
    }
  }
  execFileSync('/usr/bin/iconutil',['-c','icns',iconset,'-o',path.join(root,'Branding/Chordesk.icns')]);
  console.log('Exported dark/transparent SVG and PNG, iOS icon, About artwork, and macOS ICNS.');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
