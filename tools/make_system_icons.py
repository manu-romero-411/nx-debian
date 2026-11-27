#!/usr/bin/env python3
"""Builds the system icons (_inc/system_icons/*.svg) from separate folders and glyphs.

Inputs
  _inc/system_glyphs/<system>.svg  the glyph only, drawn in the shared 0 0 135.46666 135.46667 frame (the folder fills that frame)
  _inc/system_glyphs/folders.xml   the folder colour of every system, the colour palette and the generic folder colour
Outputs
  _inc/system_icons/<system>.svg   shadow (optional) + coloured folder + glyph
  _inc/system_icons/_folder.svg    the generic folder, used by systems without an icon of their own

ES draws a grid tile from a single image, so the folder and the glyph cannot be combined while the theme runs: they are merged here.
The folder is pastel: its palette colours are blended towards white (--mix) and their saturation is scaled (--sat).

--shadow-pad N adds a soft 0,0 shadow baked as stacked black strokes and widens the viewBox by N units per side. It is OFF by default:
the neon selector hugs the bounds of the image, so a padded icon gets its frame drawn away from the folder.

Usage: python3 tools/make_system_icons.py [--mix 0.18] [--sat 1.05] [--shadow-pad 0] [--shadow-strength 0.05]
"""
import argparse
import colorsys
import os
import xml.etree.ElementTree as ET

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_inc")
GLYPHS = os.path.join(ROOT, "system_glyphs")
ICONS = os.path.join(ROOT, "system_icons")
SVG = "http://www.w3.org/2000/svg"
NAMESPACES = {"": SVG, "inkscape": "http://www.inkscape.org/namespaces/inkscape", "xlink": "http://www.w3.org/1999/xlink"}
FRAME = 135.46666
TRANSFORM = "matrix(1.1034493,0,0,1.1034493,-7.0069641,-7.0069641)"
SCALE = 1.1034493
# Folder silhouette: the back panel with the tab, then the front panel.
PATH_BACK = "M 23.283333,6.3499999 C 13.931311,6.3499993 6.3499993,13.931311 6.3499999,23.283333 v 88.899997 c -4.4e-6,9.35202 7.5813081,16.93334 16.9333331,16.93334 h 88.899997 c 9.35203,0 16.93334,-7.58131 16.93334,-16.93334 V 35.454166 c 0,-9.352025 -7.58132,-16.933337 -16.93334,-16.933333 H 81.206412 c -4.481648,-0.007 -8.777898,-1.79035 -11.947074,-4.959387 h -5.17e-4 L 67.006245,11.309904 C 64.232581,8.5501252 60.588767,6.836045 56.694213,6.4590372 56.143566,6.3864125 55.588748,6.3499885 55.033333,6.3499999 h -0.0088 z"
PATH_FRONT = "m 23.283333,18.520833 c -9.352022,-1e-6 -16.9333337,7.581311 -16.9333331,16.933333 v 76.729104 c -4.4e-6,9.35202 7.5813081,16.93334 16.9333331,16.93334 h 88.899997 c 9.35203,0 16.93334,-7.58131 16.93334,-16.93334 V 35.454166 c 0,-9.352025 -7.58132,-16.933337 -16.93334,-16.933333 z"
GRADIENTS = (  # id, x, y1, y2
    ("folderBack", 55.033333, 6.3499999, 18.520824),
    ("folderFront", 67.73333, 18.520832, 129.11667),
)


def pastel(hex6, mix, sat):
    """Blend a colour with white (mix) and scale its saturation (sat)."""
    red, green, blue = (int(hex6[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hue, light, satur = colorsys.rgb_to_hls(red, green, blue)
    red, green, blue = colorsys.hls_to_rgb(hue, light, min(1.0, satur * sat))
    red, green, blue = (c + (1 - c) * mix for c in (red, green, blue))
    return "".join(f"{round(c * 255):02x}" for c in (red, green, blue))


def read_folders():
    """Return (palette, systems, default colour) from folders.xml."""
    root = ET.parse(os.path.join(GLYPHS, "folders.xml")).getroot()
    palette = {c.get("name"): (c.get("top"), c.get("bottom")) for c in root.find("palette")}
    systems = {s.get("name"): s.get("color") for s in root.find("systems")}
    return palette, systems, root.find("default").get("color")


def element(tag, attrs, parent=None):
    """Create an SVG element."""
    node = ET.Element(f"{{{SVG}}}{tag}", attrs)
    if parent is not None:
        parent.append(node)
    return node


def folder_nodes(colors, mix, sat, shadow_pad, strength):
    """Return (gradient defs, drawing group(s)) for a folder with the given (top, bottom) colours."""
    top, bottom = (pastel(c, mix, sat) for c in colors)
    defs = []
    for ident, x_pos, y_1, y_2 in GRADIENTS:
        grad = element("linearGradient", {"id": ident, "x1": str(x_pos), "y1": str(y_1), "x2": str(x_pos), "y2": str(y_2),
                                          "gradientUnits": "userSpaceOnUse"})
        element("stop", {"offset": "0", "style": f"stop-color:#{top};stop-opacity:1"}, grad)
        element("stop", {"offset": "1", "style": f"stop-color:#{bottom};stop-opacity:1"}, grad)
        defs.append(grad)
    groups = []
    if shadow_pad > 0:
        shadow = element("g", {"id": "imago-shadow", "transform": TRANSFORM,
                               "style": "fill:#000000;stroke:#000000;stroke-linejoin:round"})
        for step in range(int(shadow_pad) - 1, 0, -1):
            for path in (PATH_BACK, PATH_FRONT):
                element("path", {"d": path, "style": f"fill-opacity:{strength};stroke-opacity:{strength};"
                                                     f"stroke-width:{2 * step / SCALE:.3f}"}, shadow)
        groups.append(shadow)
    folder = element("g", {"id": "folder", "transform": TRANSFORM})
    element("path", {"id": "folder-back", "d": PATH_BACK, "style": "display:inline;fill:url(#folderBack)"}, folder)
    element("path", {"id": "folder-front", "d": PATH_FRONT, "style": "display:inline;fill:url(#folderFront)"}, folder)
    groups.append(folder)
    return defs, groups


def blank_svg(view_box):
    """Return an empty icon SVG (root, defs, layer)."""
    root = ET.Element(f"{{{SVG}}}svg", {"width": "512", "height": "512", "viewBox": view_box, "version": "1.1"})
    defs = element("defs", {"id": "defs1"}, root)
    layer = element("g", {"id": "layer1"}, root)
    return root, defs, layer


def write(root, name):
    """Serialise an icon next to the others."""
    ET.indent(root)
    ET.ElementTree(root).write(os.path.join(ICONS, name), encoding="utf-8", xml_declaration=True)


def build(system, colors, args):
    """Write one system icon: folder first, glyph on top."""
    pad = args.shadow_pad
    root = ET.parse(os.path.join(GLYPHS, f"{system}.svg")).getroot()
    root.set("viewBox", f"{-pad:g} {-pad:g} {FRAME + 2 * pad:.5f} {FRAME + 2 * pad:.5f}")
    defs = root.find(f"{{{SVG}}}defs")
    layer = [g for g in root.iter(f"{{{SVG}}}g") if g.get("id") == "layer1"][0]
    grads, groups = folder_nodes(colors, args.mix, args.sat, pad, args.shadow_strength)
    for index, grad in enumerate(grads):
        defs.insert(index, grad)
    for index, group in enumerate(groups):
        layer.insert(index, group)
    write(root, f"{system}.svg")


def main():
    """Rebuild every icon."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mix", type=float, default=0.18, help="blend with white, 0..1")
    parser.add_argument("--sat", type=float, default=1.05, help="saturation factor")
    parser.add_argument("--shadow-pad", type=float, default=0, help="shadow size in viewBox units (0 = no shadow)")
    parser.add_argument("--shadow-strength", type=float, default=0.05, help="opacity of each shadow layer")
    args = parser.parse_args()
    for prefix, uri in NAMESPACES.items():
        ET.register_namespace(prefix, uri)
    palette, systems, default = read_folders()
    for system, color in sorted(systems.items()):
        build(system, palette[color], args)
    pad = args.shadow_pad
    root, defs, layer = blank_svg(f"{-pad:g} {-pad:g} {FRAME + 2 * pad:.5f} {FRAME + 2 * pad:.5f}")
    grads, groups = folder_nodes(palette[default], args.mix, args.sat, pad, args.shadow_strength)
    defs.extend(grads)
    layer.extend(groups)
    write(root, "_folder.svg")


if __name__ == "__main__":
    main()
