# Chordesk · 品牌素材

2026-10-29 用户已选定新产品名 **Chordesk** 和 **B「前后双面」**图标。蓝灰与暖灰两片曲面通过中间弯曲连接处协作，表达背面手指与正面拇指的和弦控制。低饱和 Liquid Glass 方向独立于 STLAND 字标。

<img src="Chordesk-transparent.svg" width="240" alt="Chordesk B 方案透明背景 SVG 图标">

## 当前素材

| 文件 | 用途 |
| --- | --- |
| [Chordesk.svg](Chordesk.svg) | 1024 × 1024 viewBox 的原始浅底可编辑矢量主稿。 |
| [黑底 SVG](Chordesk-dark.svg) / [PNG](Chordesk-dark.png) | 黑底版本；两端 App 图标使用此方向。 |
| [透明 SVG](Chordesk-transparent.svg) / [PNG](Chordesk-transparent.png) | 无背景、保留 alpha 的玻璃图形；中英文 README、品牌页和两端关于页使用此版本。仓库展示透出 GitHub 页面本身的底色，适配明暗主题，不再出现独立黑色背景方块。 |
| [Chordesk.png](Chordesk.png) | 从 SVG 渲染的 1024 × 1024 PNG 预览，兼容需要位图的展示场景。 |
| [原始 B 方案](Chordesk-concepts/2026-10-29/B-dual-surfaces.png) | 内置 image_gen 生成的视觉参考，保留供比对。 |
| [候选对比](Chordesk-concepts/2026-10-29/index.html) | 设计探索记录，B 已选定。 |

SVG 按 B 方案重绘，由路径、渐变、遮罩和 SVG 滤镜构成，没有嵌入 PNG、外部资源、脚本或字体依赖；`rear-surface`、`front-surface`、`connecting-bridge` 是分别可编辑的图层。它保留选定方案的结构与柔和材质，不是对生成位图逐像素的无损转换。玻璃质感为静态矢量效果，不等同于系统动态 Liquid Glass。

1.16 / build 20 和 Mac 0.13.0 / build 20 已接入新名称和图标资源；构建／安装状态见 [验证记录](../docs/VALIDATION-1.16.md)。继续保留原 bundle ID、签名、配对与安装路径。

`scripts/export-branding.cjs` 从矢量主稿生成深色／透明 SVG、PNG、iOS 1024 图标及 Mac ICNS。需要 Node.js、Sharp 和 macOS iconutil。透明 SVG 不包含背景矩形；PNG 预览保留 alpha。玻璃折射为静态效果，不能动态折射任意背后的网页内容。

可用支持 SVG 滤镜的浏览器查看、用矢量编辑器修改。PNG 预览使用 Sharp 渲染 SVG 生成；四个探索方向的完整生成提示词见 [prompts.json](Chordesk-concepts/2026-10-29/prompts.json)。

## 原 ChordRemote 图标（历史方案，用户已要求重新设计）

`ChordRemote-master.png` 是内置 image_gen 工具生成的原始图；App 采用 1024 × 1024 导出图，macOS 图标打包为 `ChordRemote.icns`。系统负责 iOS 图标遮罩。

C 形的两层曲面代表前后协作；红、蓝、黄三个触点代表同时按住的“和弦”。配色和黑色几何轮廓呼应 STLAND 个人品牌。图标不是对已验证手势数量的声明。

STLAND 彩色字标、线框字标和黑色符号来自用户指定的另一产品对话，按用户授权原样复制到 `iPhoneDuoDemo/Resources/Brand/`；原文件不修改。两端“关于 Chordesk”显示“STLAND present · STLAND 出品”。品牌不遮挡远程桌面。

## 最终生成提示词

Use case: logo-brand. Create a production app icon for ChordRemote, a Duo folding phone remote-desktop app: back fingers hold a chord to alter the front thumb's touch control. Original distinctive symbol: two elegant interlocking curved bands forming a clear open C, subtly suggest the front and back planes of a device. Three large fingertip/contact nodes integrated into the form express a chord held simultaneously. Inspired by the creator STLAND's geometric Bauhaus / black monogram identity with precise primary red, blue and yellow accents. A strong restrained black sculptural C with three coloured contacts on an opaque warm ivory background. Premium minimal Apple-platform aesthetic, very subtle glass-like depth on the coloured contacts, strong flat silhouette and bold generous forms readable at 32px. Perfectly centered isolated single symbol with generous optical breathing room. 1024 square canvas, no external rounded app-icon mask, no border. No text, no letters other than the implied C, no hands, no music notation, no tiny details, no device mockup, no gradients filling the background, no watermark.
