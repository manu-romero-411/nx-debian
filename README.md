# es-theme-imago (working name)

EmulationStation theme for Batocera / RetroBat / Retrobox, inspired by Cocoon (Android) and the 3DS home screen.
Format version 7 (batocera-emulationstation).

## Layout
```
theme.xml                        entry point; declares the options (subsets)
_inc/colorsets/*.xml             6 palettes (variables: bg, tile, accent, text, subText, dimText, box, tone, scheme)
_inc/branding/*.xml              brand logo selection (variables only)
_inc/options/                    option variable files (banner on/off + height, rows, logo region, wallpaper, tiles, list, geometry)
_inc/options/geometry.xml        every icon-view coordinate derived from bOn / bannerPct / rows (ordered variables: edit with care)
_inc/layout/common.xml           background, help bar, game tiles, menu
_inc/layout/chrome.xml           top-right status capsule (network, battery, clock; iconic icons) + brand logo on its left
_inc/layout/system-grid.xml      system view: optional banner + cartel + icon grid (parametric)
_inc/layout/system-carousel.xml  system view: single-row carousel (guarded by `if="${sysCarousel} == 1"`)
_inc/layout/gamelist-grid.xml    "Icons" view of the game list: banner (console art + game/console logo) / cartel / icon grid
_inc/layout/gamelist-common.xml  built-in `basic` (centred list) + `detailed`: background, console logo, list card (shadow + body + sheen), iconic-style rows, hidden metadata
_inc/layout/gamelist-detailed.xml  built-in `detailed` view (default): list on the right; image, info card and description card on the left
_inc/options/fontscale.xml       esFontScale (ES "Theme Font Scale", same logic as es-theme-iconic)
_inc/options/listrows-*.xml      "List rows" option (auto from the font scale, or 7-17)
_inc/options/list.xml            list geometry, row font size / corner radius, card captions (en + es)
_inc/system_icons/               <system>.svg         square icon of each system (system view tiles)
_inc/system_bg/                  <system>.png|svg|jpg Carbon console art (system view; fallback for games without image)
_inc/system_logos/               console logo, ordered <path> chain (see README.txt there)
assets/ui/                       white.png, round.png, shadow.png (card shadow nine-patch), sheen.png (card gloss), neon.png, box-<set>-*.svg
assets/branding/                 retrobat.svg, batocera.svg, retrobox.svg (PLACEHOLDERS)
```

## Options (UI Settings > Theme Configuration)
Color set / Help icons / Branding / Console logo region / **Banner** (off [default], on) / **Banner height** (30-50 %, default 40) /
**System view** (icons 1-4 rows [default 3], carousel) / **Game icons** (1-4 rows [default 3]) / List rows (auto, 7-17). Default game view:
`detailed`; `basic` and the custom **Icons** view are in the same menu (Game list view style).

## Icon views (system view and the "Icons" game view)
- **Banner** (optional, at most 2 rows of icons below it): console art (`_inc/system_bg`) as the background (in the game view: the selected game main image, cropped, when it has one); the logo goes on a tinted plate:
  the console logo in the system view, the game logo (`md_marquee`) in the game view, falling back to the console logo.
  The bottom corners are rounded (the art is drawn taller, top edge off screen, `roundCorners` = `heroRad`). Height = `bannerPct` % of the screen **height** (30-50). `bannerK` in `geometry.xml` switches the basis to the screen width (`${screen.ratio}`,
  which at 16:9 means 53-89 % of the height: only usable with 4:3 or similar).
- **Console name**: without banner it is plain text at the top-left (no plate), left-aligned with the info row below it. With the banner it goes on a centred
  *cartel* (name plate), but only when there is no logo to show (system view: no console logo; game view: neither game logo nor console logo). It depends on the LOGO only, never on the console art.
- **Info row** above the grid (always, with or without banner): system view = manufacturer . year at the left end, game count (`systemInfo`) at the right end;
  game view = game name at the left, developer and year at the right. `rowY` / `rowH` in `geometry.xml`; the grid zone starts under it.
- **Logo drop shadow**: ES has no per-image shadow, so each logo (banner logos, console logo of the list views) gets thirteen black translucent copies of it
  with zero net offset: one centre copy, a ring of 8 and 4 outer points (3 px steps `lsDx`, `lsDy`) = a soft blur right under the logo (`logo_shadow` in the generator). The stock `:/shaders/shadow.glsl` shader was not used because it cannot be tested here.
- Up to 4 rows without banner (default 3), 2 with it. Row count -> tile height (capped at 34 % of the screen height); columns = floor(width / tile height),
  so the cells fill the whole width and the icon is as big as the row allows. All of it is computed in `geometry.xml` (variables evaluate in order).
- ES `MathExpr` notes: plain variables are strings, so a sum must start with a number (`0 + ${x} + ...`) or ES concatenates; `screen.ratio` is a NAME
  ("16:9"), use `${screen.width} / ${screen.height}`; `${}` inside quotes is NOT expanded in `if` (use `${a} + '/x'`) but is in `<visible>`;
  `min/max/clamp` and `a ? b : c` exist. Round/floor are written with comparisons here.
- (old note) ES `MathExpr` has no round/min: they are written with comparisons. `<visible>` is dynamic only when it contains a binding (`{game:name}`);
  static conditions use the `if` attribute (works on views, includes and elements).

## Game count: ES drives the `systemInfo` text (not a per-system extra). In the icon system view it is the right end of the info row.
`system.releaseYear` is the localized word "Unknown" when the year is missing: test it with `> 0`, never with `!= ''`.

## Status capsule
`chrome.xml`: the native clock / battery+wifi indicators belong to the `screen` view (hidden there, as iconic does); a stackpanel with `clock`, `batteryText`, `batteryIcon` and `networkIcon` inside a rounded card, top right. The built-in clock is moved off screen
and the built-in battery indicator hidden (same approach as es-theme-iconic). Icons are iconic's (`assets/icons/battery-*.svg`, `network-icon-*.svg`).

## Artwork lookup
- icon: _inc/system_icons/<system.theme>.svg
- console art: _inc/system_bg/<system.theme>.jpg
- console logo: ordered list of `<path>` in the layouts (last existing file wins), same logic as es-theme-iconic. Variables `logoRegion`
  (eu/us/jp, option "Console logo region") and `logoColorScheme` (dark/light, set per colour set). Full order in `_inc/system_logos/README.txt`.
  No generated folders. NOTE: `firstfile()` only works inside expressions (`<visible>`), never as a `<path>` value.
- `python3 tools/build_assets.py` only copies system_bg/collections, creates icon aliases and the wallpaper crops.

## List views (Basic / Detailed)
- Look: Cocoon + es-theme-iconic. Cards (list, info, description, cartel, plate) = soft shadow (`shadow.png` nine-patch, 24 px margin) + flat body
  tinted by the colour set (`panelTop`, 1 px `panelEdge`) + vertical gloss (`sheen.png`, tinted `panelBot`). Every colour set defines the texture
  variables (`panelTop/Bot/Edge`, `shadowColor`, `rowSel/rowSelEdge`, `rowSep`, `thumb`). `python3 tools/make_shadow.py` regenerates the shadow.
- Rows: item template with a flat rounded pill + hairline for the selected row and hairline separators; `roundCorners` of a rectangle is in PIXELS.
- Scrollbar: 0.45 % wide, `${thumb}`, drawn in the right padding of the card. ES quirk (not fixable from a theme): with an item template the thumb
  follows the cursor about two rows late, and it hides 1.5 s after the last move.
- `rectangle` and `ninepatch` ignore `origin`: give explicit top-left positions .
- A variable whose value contains `${` is evaluated as a math expression (`${tile}E6` would become a number): colours with alpha are written inline.
- `detailed`: console logo centred over the game image, image on its own card (same shadow as the others); the left column (logo, image card + info card side by side, description card) spans exactly the height of the list card (0.13-0.93); gaps between cards are >= 0.03 so shadows do not stack.
- In `detailed` ES draws every metadata label/field the theme does not define: `gamelist-common.xml` hides them all and each view re-enables its own.
- Entries without game data (the `. .` parent folder) skip the item template and use the built-in selector.

## Known limits / to verify
- System grid: in Batocera ES the system-view grid is `<imagegrid name="imagegrid">` (confirmed in es-theme-tiled, systemview/grid.xml;
  `systemgrid` and `systemcarousel` do NOT work: the latter logs "mismatched theme type ... expected carousel").
  Still unverified: tile image source (assumed `<image name="logo">`), `autoLayout`/`scrollDirection` support in this view.
  Carousel stays as fallback.
- Nothing here could be run in a real ES: check F5 reload on a Batocera build (`firstfile()` inside `if`/`<visible>`, `clipRect` of the banner,
  ninepatch `cornerSize` in px, `exists({game:marquee})`, `imagegrid` column count as an integer).
- No fonts are bundled (default ES font). Add a TTF and a `<fontPath>` if wanted.
- Logos in assets/branding are placeholders; use the official artwork you are allowed to use.

Renaming the theme = renaming the folder; all paths use `${themePath}` or are relative.

## Wallpapers (assets/wallpapers/)
- `<name>.svg` 16:9 (p. ej. 1280x720) = fondo a pantalla completa, capa `e_wallpaper` (z 1, sobre el color plano `bg`). **Debe estar aplanado** (sin `<use>`, `<clipPath>`, filtros ni capas ocultas: NanoSVG no los soporta). Si lo exportas de Inkscape: `python3 tools/flatten_svg.py original.svg assets/wallpapers/<nombre>.svg`.
- Cada colorset elige el suyo en `_inc/colorsets/*.xml` (`wallpaper`, `wallpaperB1`, `wallpaperB2`). Hoy: Black -> `dark.svg`; el resto -> `<colorset>.svg` (la misma rejilla de cuadrados que Black, recoloreada: base = `bg` oscurecido por `dim` (rojo, azul y morado van mas oscuros que el `bg` plano), cuadrados = base aclarada, vineta = base oscurecida). Se regeneran con `python3 tools/make_wallpapers.py` (paletas en el diccionario `SETS` del script).
- `-b1`/`-b2` crops are no longer used (the banner is clipped with `clipRect`, nothing is drawn under it).
- Opcion de tema `Wallpaper: on/off` (off = usa `none.png`).
- Para anadir otro: copia `assets/wallpapers/<name>.svg`, ejecuta el script y apunta las 3 variables del colorset a `<name>.svg`, `<name>-b1.svg`, `<name>-b2.svg`.

## Iconos de sistema (_inc/system_icons/)
- `_folder.svg` es la carpeta generica que se usa cuando un sistema no tiene icono propio (el tema pone primero `_folder.svg` y despues `<system>.svg`; ES se queda con el ultimo `<path>` que existe).
- The icons in this folder are GENERATED: `python3 tools/make_system_icons.py [--mix 0.18] [--sat 1.05]`. Do not edit them by hand.
  - `_inc/system_glyphs/<system>.svg`: the glyph only (white shapes), drawn in the 0 0 135.46666 135.46667 frame that the folder fills. To add a system, draw its glyph in that frame (Inkscape) and save it here.
  - `_inc/system_glyphs/folders.xml`: the folder colour of every system (`<system name="snes" color="spring-green"/>`), the palette (original saturated top/bottom colours) and the colour of the generic folder. Not read by ES.
  - The script draws the folder in that colour (pastel: blended with white by `--mix`, saturation scaled by `--sat`), puts the glyph on top and writes `_inc/system_icons/<system>.svg` and `_folder.svg` (generic folder, now the same size as the others).
  - ES draws a grid tile from ONE image, so folder and glyph cannot be combined while the theme runs; that is why they are merged at generation time.
  - `--shadow-pad N` bakes a soft 0,0 shadow and widens the viewBox, but it is off: the neon selector hugs the image bounds, so a padded icon gets its frame away from the folder.
  - `app_j2me_loader.svg` is a hand-made icon (own shape and gradient); the script does not touch it. `_template_app.svg` is its template.

## Selector neon y tiles (assets/ui/neon.png, _inc/options/tiles.xml)
- Los tiles ya no tienen placa: icono/caratula a todo el ancho o alto del tile (`imageSizeMode=maxSize`). El seleccionado lleva un contorno neon que rodea
  solo la imagen (`selectionMode=image`), tenido con `${neon}` (variable de cada color set). Si tu ES ignora `selectionMode`, el neon rodeara el tile entero.
- `neon.png` es un nine-patch (nucleo + resplandor solo hacia fuera). Se regenera con `python3 tools/make_neon.py [BAND] [STROKE]`;
  `BAND` debe ser igual a `tPad` (px entre la imagen y el borde del tile = `backgroundCornerSize`).
- `tiles.xml`: `tPad` (20), `tZoom` (1.06, zoom del seleccionado) y `gPad` (holgura izq/arriba/dcha/abajo del grid, relativa a la pantalla).
  Si el zoom o el neon se cortan en los bordes del grid, sube `gPad`; si quieres iconos mas grandes, baja `tPad` (y regenera el PNG con el mismo BAND).
- El grid ocupa el 100 % del ancho (`pos 0`, `size 1`) y, en vertical, `gPad` extra arriba y abajo (la zona util es la de antes). Geometria: `geometry.xml`.

## Fonts (assets/fonts/, _inc/options/fonts.xml)
Poppins, all 18 files. Elements never hard-code a file: they use a **role variable** from `_inc/options/fonts.xml`, so a weight can be changed in one place.

| Role variable | Weight | Used by |
|---|---|---|
| `fontMenuItem` | Light | main menu selectable entries (`menutext`) |
| `fontMenuGroup` | Medium | menu group names (`menugroup`, coloured with `${neon}`) |
| `fontMenuTitle` | Medium | menu title (`menutitle`) |
| `fontMenuSmall` | Regular | menu small text and footer (`menutextsmall`, `menufooter`) |
| `fontTitle` | Bold | console and game titles: info strip, name over the banner box, carousel title |
| `fontInfo` | Regular | maker, developer, year, game count |
| `fontUI` | Medium | clock, help bar |

Raw weights (`fontThin` ... `fontBlack`) are also defined for new elements. Poppins is much wider than the default ES font, so sizes were reduced
(titles 0.030, info 0.024, help 0.026, banner box name 0.040 via `bFS1/bFS2` in `banner-on/off.xml`, menu 0.021-0.036). Poppins is released under the SIL Open Font License:
keep its license text if you redistribute the theme.

## Menu icons (assets/icons/)
The 14 menu icons come from es-theme-iconic (white SVG, 24x24; ES tints them with the menu text colour, so they work on dark and light colour sets),
wired in the `menu` view of `_inc/layout/common.xml` (`menuIcons` + `menuTextEdit`). `menu-icon-controller.svg` and `gamepad.svg` are the custom controller icon
(glyph scaled to 22/24 of the box so it matches the others). Use that same icon for anything related to controllers/gamepads
(`gamepad.svg`, `gun.svg`, `wheel.svg` are the native controller indicator: without `imagePath` ES draws a plain grey square per pad at the top-left; the `screen` view places it in the footer.)

## Help icons (_inc/help/, option "Help icons")
Same option and logic as es-theme-recalboxy (subset `helpicons`): Default (Batocera) / Xbox / PlayStation / SNES / Generic 4, 6 and 8 buttons / SNES alt / Xbox One / Arcade.
`default.xml` is an empty preset (Batocera's own icons, tinted with the help colour). The others override the `helpsystem name="help"` icons and are included in `theme.xml`
AFTER `common.xml`. Xbox, PlayStation and SNES map the *physical position* of Batocera's buttons (A = east, B = south, X = north, Y = west) and are full-colour icons
(`iconColor` FFFFFFFF, not tinted); the generic sets keep the theme tint (`${subText}`). Font and size of the help bar stay in `common.xml`.

**Licence:** the package mixes licences (own work, CC BY-SA 4.0 from Wikimedia Commons, CC BY-NC-SA from Recalbox/Carbon/Iconic). Read `NOTICE.md`, `_inc/help/NOTICE.md` and `_inc/help/CREDITS-wikimedia.txt` before redistributing: the package is non-commercial because of its third-party parts.

- Sums that reach ES as `0 + ...` must contain at least one `${}`: a variable whose value has no `${` is NOT evaluated, so `0 + 0.5 + (0)` stays a literal string and the position falls back to 0. Use numbers directly instead.

## Loading and game launch screens (`splash.xml`, `gamesplash.xml`, `assets/splash/`)
- `splash.xml` is the loading screen. ES loads it without `theme.xml`, so it re-declares the `branding` and `colorset` subsets (keep the order in sync with `theme.xml`). Default branding: **Retrobox** (also RetroBat, Batocera). `assets/splash/<brand>[-dark|-light].png|svg` come from es-theme-iconic (CC0), without its `_default.png`; `Light gray` uses the light variants, the other colour sets the dark ones. Assets of brands not selectable yet (knulli, recalbox, emuelec) are kept for later.
- `gamesplash.xml` is what ES shows while a game launches: plain black, the game image (replaced by a transparent PNG) and name (alpha 0) are hidden.
- The launch *transition* ("GAME LAUNCH TRANSITION") is a user setting of ES, not a theme property: a theme cannot default it to `instant`. Set it once in the UI settings.
- Untested in a real ES: nothing here has been run in EmulationStation (validated with xmllint and rendered previews only).
