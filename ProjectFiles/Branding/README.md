# Chordesk artwork / 品牌素材

The selected icon uses two interlocking surfaces to represent front/rear chord control. The installed app icon keeps the black background; repository pages use the transparent SVG.

| Asset | Use |
| --- | --- |
| `Chordesk.svg` | Editable vector master |
| `Chordesk-dark.svg`, `Chordesk-dark.png`, `Chordesk.icns` | Black-background app icon exports |
| `Chordesk-transparent.svg`, `Chordesk-transparent.png` | Repository and website artwork that follows the page background |
| `STLAND-wordmark.svg` | Transparent monochrome creator wordmark |
| `Chordesk-concepts/`, `Chordesk-glass-preview/` | Design references; not shipped as app code |

Run `scripts/export-branding.cjs` from the repository to regenerate exports using Node.js, Sharp and macOS iconutil. Runtime copies are placed in `ProjectFiles/Chordesk/Assets.xcassets/` and `ProjectFiles/Chordesk/Resources/Brand/`.

SVG uses static paths, gradients and filters; the artwork is not a live system Liquid Glass material. Original design history is available in Git.
