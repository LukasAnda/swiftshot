# Device frames

Swiftshot puts screenshots into Apple's official device bezels, the
[Product Bezels](https://developer.apple.com/design/resources/#product-bezels) from Apple's design
resources. It has two modes: plain frames for websites and press kits, and App Store screenshots
with a background and a localized title.

```
swiftshot --frame                          # render, then frame (plain)
swiftshot --frame appstore                 # render, then App Store screenshots
swiftshot frame fastlane/screenshots       # frame an existing folder (plain)
swiftshot frame fastlane/screenshots --frame appstore
```

## Modes

### Plain

The device with the screenshot in it, at the bezel's own size, transparent around the device. As
Apple ships it: no shadow, reflection or other effects.

Output: `<output>-framed/<language>/<name>_framed.png`, e.g.
`screenshots-framed/en-US/iPhone 17 Pro Max-Welcome_framed.png`. Use `--frame-output` to change the folder.

Plain frames stay out of the screenshots folder on purpose: they are not App Store sizes and they
have transparency, and `fastlane deliver` checks every image in a language folder.

### App Store

An image at the exact size App Store Connect accepts for the device, with no transparency:

- a background (colour or image),
- an optional keyword and a title, above or below the device,
- the framed device, scaled to fit.

The text never covers the device. Long titles wrap and shrink to fit.

Output: `<output>/<language>/<name>_framed.png`, next to the original.

The canvas is the screenshot's own size when App Store Connect accepts it. Every swiftshot
full-screen capture of a current device is such a size: 1320×2868 for the iPhone 17 Pro Max (6.9"),
2064×2752 for the 13-inch iPad Pro. Otherwise the canvas is the largest accepted size with the
closest aspect ratio.

| Display class | Accepted sizes (portrait; landscape is the same rotated) |
|---|---|
| iPhone 6.9" | 1320×2868, 1290×2796, 1260×2736 |
| iPhone 6.5" | 1284×2778, 1242×2688 |
| iPhone 6.3" | 1206×2622, 1179×2556 |
| iPhone 6.1" | 1170×2532, 1125×2436, 1080×2340 |
| iPhone 5.5" | 1242×2208 |
| iPhone 4.7" | 750×1334 |
| iPhone 4" | 640×1136 |
| iPhone Duo | 1398×2034 (outer), 2007×2853 (inner) |
| iPad 13" | 2064×2752, 2048×2732 |
| iPad 11" | 1668×2420, 1668×2388, 1640×2360, 1488×2266 |
| iPad 10.5" | 1668×2224 |
| iPad 9.7" | 1536×2048 |

Source: [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

Apple Watch screenshots stay unframed in App Store mode: App Store Connect takes the bare screen
(422×514 for Ultra 3). Plain mode frames them.

### What is framed

- Full-screen screenshots, portrait and landscape. Landscape uses Apple's landscape bezel.
- Not partial-size previews (`.sizeThatFitsLayout`, `.fixedLayout`) or `--full-length` captures.
  They are left as they are.
- Devices without an Apple bezel stay unframed. Swiftshot lists them in one warning.

## Options

| Flag | `swiftshot.json` | |
|---|---|---|
| `--frame [plain\|appstore\|none]` | `"frame": "plain"` (or `true`) | Mode. `--frame` alone means plain. |
| `--frame-color <colours>` | `"frame_color"` | Bezel colour: `"Deep Blue"` for every device, `"iPad Pro 13-inch (M5)=Silver"` for one. Comma separated. In JSON a string, a list, or `{"device": "colour"}`. |
| `--framefile <path>` | `"framefile"` | frameit `Framefile.json`. Default: looked up like frameit does (below). |
| `--frame-background <#RRGGBB\|image>` | `"frame_background"` | App Store background. Overrides the Framefile's. |
| `--frame-output <dir>` | `"frame_output"` | Folder for plain frames. Default `<output>-framed`. |
| `--frame-cache <dir>` | `"frame_cache"` | Bezel cache. Default `~/Library/Caches/swiftshot/frames`. |
| `--accept-bezel-license` | `"accept_bezel_license": true` | Accept Apple's license without the prompt (CI). |

`swiftshot frame [<dir>]` takes the same options. `<dir>` defaults to `--output`. It reads device
names from `swiftshot-report.json` when the folder has one, and from the file names otherwise, so it
also frames screenshots from other tools in the deliver layout.

Per screenshot, with the existing `screens` rules:

```
swiftshot --frame appstore --screen "Debug*: frame=none" --screen "Hero: frame=plain"
```

```json
"screens": [{ "preview": "Debug*", "frame": "none" }]
```

## Titles

Swiftshot reads `title.strings` and `keyword.strings` the way frameit does. It looks in the
language folder first, then the screenshots folder, then the folder above it.

```
fastlane/screenshots/en-US/title.strings
"Welcome" = "Build habits that stick";
"Stats" = "See your progress";
"Stats landscape" = "Your week at a glance";
```

- A key matches a screenshot when the file name contains it (ignoring case). The longest matching
  key wins, so `Stats landscape` beats `Stats`.
- Files can be UTF-8 or UTF-16, with or without a byte order mark.
- `\n` in a value starts a new line.
- No text in `.strings` falls back to the Framefile's `title.text` / `keyword.text`.
- No title at all: the device on its background.

Fonts default to the system font (bold for the title), with the language's own fallbacks, so
Arabic, Hebrew, Japanese and so on render correctly and right-to-left text runs right to left.

Defaults without a Framefile:
- background `#F2F2F7` for light screenshots and `#1C1C1E` for dark ones,
- black or white text, whichever contrasts with the background,
- padding 7 % of the short side.

## Framefile.json

Swiftshot reads fastlane frameit's
[Framefile.json](https://docs.fastlane.tools/actions/frameit/#advanced-usage-optional). It looks
for one in the language folder, the screenshots folder and two levels above it, like frameit, unless
`--framefile` names one.

```json
{
  "default": {
    "background": "background.jpg",
    "padding": "6%",
    "title": { "color": "#1D1D1F", "font": "fonts/Inter-Bold.ttf" },
    "keyword": { "color": "#5E5CE6" },
    "stack_title": true
  },
  "data": [
    { "filter": "Stats landscape", "title_below_image": true },
    { "filter": "iPad", "title": { "font_size": 120 } },
    { "filter": "de-DE", "background": "#000000" }
  ]
}
```

Every `data` entry whose `filter` is part of the screenshot's path is merged over `default`, in
file order: later entries win, nested objects merge. The path is relative to the screenshots
folder, e.g. `de-DE/iPad Pro 13-inch (M5)-Stats.png`, so filters can name a language, a device or a
preview. Like frameit, filters are case-sensitive. Relative `font` and `background` paths are
relative to the Framefile.

Supported keys:

| Key | |
|---|---|
| `background` | An image (scaled to fill, centred) or a `#RRGGBB` colour. |
| `title`, `keyword` | `text`, `color` (`#RRGGBB`), `font` (a font file or a font name), `font_size` (pixels), `fonts` (`[{ "font": …, "supported": ["ja", …] }]`, per language). |
| `padding` | Pixels, `"AxB"` (horizontal × vertical) or a percentage of the short side, e.g. `"5%"`. |
| `title_below_image` | Text below the device. |
| `stack_title` | Keyword above the title instead of before it. |
| `show_complete_frame` | `true` (default): the whole device fits. `false`: the device is as wide as the padding allows and runs off the edge away from the text. |
| `title_min_height` | Minimum height of the text area: pixels or a percentage. |
| `font_scale_factor` | Title size as a fraction of the canvas width, when no `font_size` is given. |
| `interline_spacing` | Extra space between lines, in pixels. |
| `frame` | Bezel colour, frameit style (`"BLACK"`, `"SPACE_BLACK"`…). `--frame-color` wins. |

Swiftshot warns about other keys and ignores them, for example `offset`, `use_platform`,
`force_device_type` and `font_weight`.

Differences from frameit:
- `padding` is in output pixels, with no extra factor for @3x devices.
- `show_complete_frame` defaults to `true`.
- The default title size follows the canvas area (about 107 px on 6.9").
- A screenshot without a title is still framed.

## Colours

Names are Apple's. `--frame-color` ignores case, spaces, `-` and `_`. A partial name picks the first
match in alphabetical order (`Natural` picks a natural titanium watch). If a model doesn't have the
colour, swiftshot uses its default and lists the colours it does have.

| Device | Colours (default in bold) |
|---|---|
| iPhone 18 Pro, 18 Pro Max | **Black**, Burgundy, Glacier, Silver |
| iPhone 17 Pro, 17 Pro Max | Cosmic Orange, **Deep Blue**, Silver |
| iPhone 17 | **Black**, Lavender, Mist Blue, Sage, White |
| iPhone Air | Cloud White, Light Gold, Sky Blue, **Space Black** |
| iPhone 16 Pro, 16 Pro Max | **Black Titanium**, Desert Titanium, Natural Titanium, White Titanium |
| iPhone 16, 16 Plus | **Black**, Pink, Teal, Ultramarine, White |
| iPhone Duo | **Night Sky**, Star White |
| iPad Pro 11-inch, 13-inch (M5, M4) | Silver, **Space Black** |
| iPad Air 11-inch, 13-inch (M4, M3, M2) | Blue, Purple, **Space Gray**, Starlight |
| iPad mini (A17 Pro) | Blue, Purple, **Space Gray**, Starlight |
| iPad (A16) | Blue, Pink, **Silver**, Yellow |
| Apple Watch Ultra 3 (49mm) | Black or Natural case with an Alpine Loop, Milanese Loop, Ocean Band or Trail Loop, e.g. **Black + Ocean Band Black**, Natural + Trail Loop Green Neon |
| Apple Watch Ultra 2, Ultra (49mm) | Black or Natural with an Alpine Loop, Titanium Milanese Loop, Ocean Band or Trail Loop, e.g. **Black + Ocean Band Black** |
| Apple Watch Series 11, 10 (42mm, 46mm) | Aluminum (Jet Black, Rose Gold, Silver, Space Gray) or Titanium (Gold, Natural, Slate) with a Sport Band, Sport Loop, Milanese Loop or Magnetic Link, e.g. **Aluminum Jet Black + Sport Band Black** |

## Supported devices

The table above. iPad Pro (M4) has the same body and screen as (M5), iPad Air (M2, M3) as (M4),
Apple Watch Series 10 as Series 11, and Apple Watch Ultra as Ultra 2. They use those bezels.

Apple ships no bezels for other devices, for example iPhone 17e, 16e, iPhone 15 and older, iPhone
SE, older iPads and Apple Watch SE. Their screenshots stay unframed and swiftshot says so in one
warning. iPhone Duo is framed with its outer (closed) display.

## fastlane deliver

When a language folder has any `*_framed.png`, `deliver` uploads only the framed files plus the
Apple Watch screenshots, and skips the rest. It then rejects any file that is not an accepted size.
Swiftshot follows that:

- App Store frames are named `<name>_framed.png` next to the originals, so `deliver` uploads them.
- A screenshot that stays unframed in such a folder gets an identical `<name>_framed.png` copy, so
  it is not dropped. That covers a device without a bezel and `frame=none`.
- Plain frames go to their own folder.
- A rendering run removes frames left over from earlier runs, which `deliver` would otherwise
  upload. Frames newer than their screenshot are kept.
- `--clear` deletes images only. `.strings` files and a `Framefile.json` in the language folders
  stay.

## Download and cache

Apple publishes one disk image per family. Most of each image is Photoshop files. Swiftshot
downloads only the families your devices need, once, in parallel and during the build. It mounts
each image read-only, keeps the PNGs, and deletes the image. hdiutil checks the image's checksums.
Swiftshot records each PNG's size and SHA-256 in `manifest.json`, and downloads a family again if a
file is missing or its size changed.

| Family | Download |
|---|---:|
| iPad Pro (M5) | 7 MB |
| iPad mini (A17 Pro) | 8 MB |
| iPad (A16) | 11 MB |
| iPad Air (M4) | 12 MB |
| iPhone 18 | 144 MB |
| Apple Watch Ultra 2 | 186 MB |
| iPhone 17 (17, 17 Pro, 17 Pro Max, Air) | 265 MB |
| iPhone 16 | 273 MB |
| Apple Watch Ultra 3 | 329 MB |
| Apple Watch Series 11 | 358 MB |
| iPhone Duo | 453 MB |

The cache keeps about 2–16 MB of PNGs per family, in `~/Library/Caches/swiftshot/frames/1/`.
On CI, cache that folder:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/Library/Caches/swiftshot/frames
    key: swiftshot-frames-1
- uses: LukasAnda/swiftshot@v0.2.0
  with:
    args: --frame appstore --accept-bezel-license
```

Framing itself is fast. Compositing takes about 6 ms per image; writing the PNG takes most of the
time. On an M4 Pro, 34 frames of an iPhone 17 Pro Max and a 13-inch iPad take 0.9 s.

## License

The bezels are Apple's. Swiftshot does not include or redistribute them: it downloads them from
Apple on your machine. They come under the
[Apple Design Resources License](https://developer.apple.com/support/downloads/terms/apple-design-resources/Apple-Design-Resources-License-20230621-English.pdf),
which you accept once, at the prompt or with `--accept-bezel-license`. Use the frames as Apple's
[marketing guidelines](https://developer.apple.com/app-store/marketing/guidelines/) describe.
Plain mode keeps the bezels as Apple ships them.
