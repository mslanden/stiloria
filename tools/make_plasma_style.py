"""Write the Stiloria Plasma style: glass panels and menus, navy pill selections
with a gold edge, pill fields and buttons.

usage: python3 tools/make_plasma_style.py   (from the repo root)

Only the files that change the look are written; Plasma takes everything else
from Breeze. Every shape is drawn from the color scheme (ColorScheme-* classes),
so one style serves both Stiloria Day and Stiloria Night.

Plasma draws these as 9-slice frames: for each prefix, elements named
<prefix>-topleft, -top, -topright, -left, -center, -right, -bottomleft,
-bottom and -bottomright, whose bounding boxes are the slice sizes, plus
hint-* elements whose sizes set content margins. The shapes here are built
geometrically so every slice's bounding box is exact.
"""
import gzip, json, pathlib

ROOT = pathlib.Path("system_files/usr/share/plasma/desktoptheme/stiloria")
K = 0.5523  # cubic Bézier control distance for a quarter circle
E = 4  # length of the stretched edge slices and of the center

STYLE = """<defs><style type="text/css" id="current-color-scheme">
.ColorScheme-Background { color:#f4efe6; }
.ColorScheme-Text { color:#1b2547; }
.ColorScheme-Highlight { color:#23315f; }
.ColorScheme-ViewBackground { color:#fbf8f2; }
.ColorScheme-ViewText { color:#1b2547; }
.ColorScheme-ViewFocus { color:#c99a45; }
.ColorScheme-ViewHover { color:#d9a74a; }
.ColorScheme-ButtonBackground { color:#eee7da; }
.ColorScheme-ButtonFocus { color:#c99a45; }
.ColorScheme-ButtonHover { color:#d9a74a; }
</style></defs>"""


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


class Svg:
    def __init__(self):
        self.parts = []
        self.y = 0  # frames are stacked vertically on the canvas
        self.width = 0

    def shape(self, d, cls, opacity):
        return f'<path class="{cls}" style="fill:currentColor;fill-opacity:{fmt(opacity)}" d="{d}"/>'

    def frame(self, prefix, S, R, layers, hints=None, spacer=True):
        """layers: (cls, opacity, outer inset, inner inset or None for a fill)."""
        ox, oy = 0, self.y
        name = (prefix + "-") if prefix else ""
        pos = {"topleft": (0, 0), "top": (S, 0), "topright": (S + E, 0), "left": (0, S), "center": (S, S),
               "right": (S + E, S), "bottomleft": (0, S + E), "bottom": (S, S + E), "bottomright": (S + E, S + E)}
        for part, (px, py) in pos.items():
            x0, y0 = ox + px, oy + py
            w = S if part in ("topleft", "topright", "left", "right", "bottomleft", "bottomright") else E
            h = S if part in ("topleft", "topright", "top", "bottom", "bottomleft", "bottomright") else E
            items = []
            if spacer:
                items.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" style="fill:#000;fill-opacity:0"/>')
            for cls, opacity, a, b in layers:
                d = self.slice_path(part, x0, y0, S, R, a, b)
                if d:
                    items.append(self.shape(d, cls, opacity))
            self.parts.append(f'<g id="{name}{part}">' + "".join(items) + "</g>")
        size = 2 * S + E
        if hints:
            hx = ox + size + 8
            for i, (hint, value) in enumerate(hints.items()):
                horizontal = hint.endswith(("left-margin", "right-margin", "left-inset", "right-inset"))
                w, h = (value, 2) if horizontal else (2, value)
                self.parts.append(f'<rect id="{name}hint-{hint}" x="{hx + i * 24}" y="{oy}" width="{w}" height="{h}" style="fill:#000;fill-opacity:0"/>')
        self.width = max(self.width, size + 8 + 24 * len(hints or {}) + 40)
        self.y += size + 8

    def slice_path(self, part, x0, y0, S, R, a, b):
        def corner(mx, my):
            # Top-left corner geometry in local coordinates, mirrored by (mx, my).
            def P(x, y):
                x = S - x if mx else x
                y = S - y if my else y
                return f"{fmt(x0 + x)},{fmt(y0 + y)}"
            ra = max(R - a, 0)
            outer = [f"M{P(a, S)}", f"L{P(a, R)}", f"C{P(a, R - K * ra)} {P(R - K * ra, a)} {P(R, a)}", f"L{P(S, a)}"]
            if b is None:
                return " ".join(outer + [f"L{P(S, S)}", "Z"])
            rb = max(R - b, 0)
            inner = [f"L{P(S, b)}", f"L{P(R, b)}", f"C{P(R - K * rb, b)} {P(b, R - K * rb)} {P(b, R)}", f"L{P(b, S)}", "Z"]
            return " ".join(outer + inner)

        def rect(x, y, w, h):
            return f"M{fmt(x0 + x)},{fmt(y0 + y)} h{fmt(w)} v{fmt(h)} h{fmt(-w)} Z" if w > 0 and h > 0 else ""

        inner = S if b is None else b
        if part == "topleft":
            return corner(False, False)
        if part == "topright":
            return corner(True, False)
        if part == "bottomleft":
            return corner(False, True)
        if part == "bottomright":
            return corner(True, True)
        if part == "top":
            return rect(0, a, E, inner - a)
        if part == "bottom":
            return rect(0, S - inner, E, inner - a)
        if part == "left":
            return rect(a, 0, inner - a, E)
        if part == "right":
            return rect(S - inner, 0, inner - a, E)
        if part == "center":
            return rect(0, 0, E, E) if b is None else ""
        return ""

    def element(self, el):
        self.parts.append(el)

    def write(self, rel):
        path = ROOT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        body = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.y}" '
                f'viewBox="0 0 {self.width} {self.y}">\n{STYLE}\n' + "\n".join(self.parts) + "\n</svg>\n")
        # A fixed timestamp keeps the image build reproducible.
        with open(path, "wb") as raw, gzip.GzipFile(filename="", mode="wb", compresslevel=9, fileobj=raw, mtime=0) as f:
            f.write(body.encode())
        print("wrote", path)


def shadow(svg, S, R, strength):
    """A soft shadow around a glass frame: radial at the corners, linear on the
    sides. KWin draws it outside the window, so the inside is left empty."""
    ox, oy = 0, svg.y
    defs = []
    for part, (px, py, cx, cy) in {"topleft": (0, 0, S, S), "topright": (S + E, 0, S + E, S),
                                    "bottomleft": (0, S + E, S, S + E), "bottomright": (S + E, S + E, S + E, S + E)}.items():
        gid = f"sh-{part}-{oy}"
        defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{ox + cx}" cy="{oy + cy}" r="{S}">'
                    f'<stop offset="0" stop-color="#000" stop-opacity="{strength}"/>'
                    f'<stop offset="0.45" stop-color="#000" stop-opacity="{strength * 0.45:.3f}"/>'
                    f'<stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>')
        svg.element(f'<rect id="shadow-{part}" x="{ox + px}" y="{oy + py}" width="{S}" height="{S}" style="fill:url(#{gid})"/>')
    for part, (px, py, w, h, x1, y1, x2, y2) in {
            "top": (S, 0, E, S, 0, S, 0, 0), "bottom": (S, S + E, E, S, 0, S + E, 0, 2 * S + E),
            "left": (0, S, S, E, S, 0, 0, 0), "right": (S + E, S, S, E, S + E, 0, 2 * S + E, 0)}.items():
        gid = f"sh-{part}-{oy}"
        defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{ox + x1}" y1="{oy + y1}" x2="{ox + x2}" y2="{oy + y2}">'
                    f'<stop offset="0" stop-color="#000" stop-opacity="{strength}"/>'
                    f'<stop offset="0.45" stop-color="#000" stop-opacity="{strength * 0.45:.3f}"/>'
                    f'<stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>')
        svg.element(f'<rect id="shadow-{part}" x="{ox + px}" y="{oy + py}" width="{w}" height="{h}" style="fill:url(#{gid})"/>')
    svg.element(f'<rect id="shadow-center" x="{ox + S}" y="{oy + S}" width="{E}" height="{E}" style="fill:#000;fill-opacity:0"/>')
    svg.element("<defs>" + "".join(defs) + "</defs>")
    hx = ox + 2 * S + E + 8
    for i, side in enumerate(("top", "bottom", "left", "right")):
        for j, kind in enumerate(("margin", "inset")):
            # How far the shadow reaches past the frame, and how far it starts inside it.
            value = {"margin": S - 6, "inset": R}[kind]
            horizontal = side in ("left", "right")
            w, h = (value, 2) if horizontal else (2, value)
            svg.element(f'<rect id="shadow-hint-{side}-{kind}" x="{hx + (i * 2 + j) * 24}" y="{oy}" width="{w}" height="{h}" style="fill:#000;fill-opacity:0"/>')
    svg.width = max(svg.width, 2 * S + E + 8 + 8 * 24 + 40)
    svg.y += 2 * S + E + 8


def glass(rel, R, margin, opacity, shadow_size, shadow_strength, extra=None):
    """A glass surface: translucent fill, a faint outer edge, and a lighter inner
    edge that reads as a highlight on light glass."""
    svg = Svg()
    S = R
    layers = [("ColorScheme-Background", opacity, 1, None),
              ("ColorScheme-Text", 0.10, 0, 1),
              ("ColorScheme-ViewBackground", 0.55, 1, 2)]
    hints = {"top-margin": margin, "bottom-margin": margin, "left-margin": margin, "right-margin": margin,
             "top-inset": 4, "bottom-inset": 4, "left-inset": 4, "right-inset": 4}
    svg.frame("", S, R, layers, hints)
    svg.frame("mask", S, R, [("ColorScheme-Background", 1, 0, None)])
    if extra:
        extra(svg, S, R, opacity)
    shadow(svg, shadow_size, R, shadow_strength)
    svg.element('<rect id="hint-tile-center" x="0" y="0" width="5" height="5" style="fill:#000;fill-opacity:0"/>')
    svg.write(rel)


def thick(svg, S, R, opacity):
    svg.frame("thick", S, R, [("ColorScheme-Background", opacity, 1, None), ("ColorScheme-Text", 0.10, 0, 1),
                              ("ColorScheme-ViewBackground", 0.55, 1, 2)],
              {"top-margin": 8, "bottom-margin": 8, "left-margin": 8, "right-margin": 8})


# Glass surfaces: opaque files for desktops without blur, translucent ones for blur.
for base, opacity in (("", 0.97), ("translucent/", 0.72)):
    glass(f"{base}dialogs/background.svgz", R=26, margin=12, opacity=opacity, shadow_size=30, shadow_strength=0.30)
    glass(f"{base}widgets/panel-background.svgz", R=22, margin=6, opacity=opacity, shadow_size=24, shadow_strength=0.26, extra=thick)
    glass(f"{base}widgets/tooltip.svgz", R=14, margin=8, opacity=min(opacity + 0.12, 0.97), shadow_size=18, shadow_strength=0.24)
    glass(f"{base}widgets/background.svgz", R=22, margin=12, opacity=opacity, shadow_size=24, shadow_strength=0.22)

# List items (start menu, system tray, notification history). Plasma marks the
# current item with the "hover" frame and keeps the item's own text color, so
# selections are a light navy pill (a tint, readable under dark or light text)
# with a gold edge; pressed items take a deeper tint.
svg = Svg()
R = 12  # at most half the shortest row (start menu rows are about 30px), or corners overlap
svg.frame("normal", R, R, [])
svg.frame("hover", R, R, [("ColorScheme-Highlight", 0.32, 0, None), ("ColorScheme-ViewFocus", 0.80, 0, 1.2)])
svg.frame("selected", R, R, [("ColorScheme-Highlight", 0.40, 0, None), ("ColorScheme-ViewFocus", 0.90, 0, 1.3)])
svg.frame("selected+hover", R, R, [("ColorScheme-Highlight", 0.46, 0, None), ("ColorScheme-ViewFocus", 1, 0, 1.4)])
svg.element('<rect id="hint-tile-center" x="0" y="0" width="5" height="5" style="fill:#000;fill-opacity:0"/>')
svg.write("widgets/viewitem.svgz")

# Text fields: pills, with a gold edge on focus.
svg = Svg()
R = 16
pad = {"left-margin": 14, "right-margin": 14, "top-margin": 6, "bottom-margin": 6}
svg.frame("base", R, R, [("ColorScheme-ViewBackground", 0.70, 1, None), ("ColorScheme-Text", 0.12, 0, 1)], pad)
svg.frame("hover", R, R, [("ColorScheme-ViewHover", 0.85, 0, 1.2)], pad)
svg.frame("focus", R, R, [("ColorScheme-ViewFocus", 1, 0, 1.6)], pad)
svg.frame("focusframe", R, R, [("ColorScheme-ViewFocus", 0.35, 0, 3)], pad)
svg.element('<rect id="hint-focus-over-base" x="0" y="0" width="2" height="2" style="fill:#000;fill-opacity:0"/>')
svg.element('<rect id="hint-tile-center" x="0" y="0" width="5" height="5" style="fill:#000;fill-opacity:0"/>')
svg.write("widgets/lineedit.svgz")

# Buttons: quiet pills; pressed takes the navy selection; focus is a gold edge.
svg = Svg()
R = 15
pad = {"left-margin": 12, "right-margin": 12, "top-margin": 5, "bottom-margin": 5}
svg.frame("normal", R, R, [("ColorScheme-Text", 0.07, 1, None), ("ColorScheme-Text", 0.10, 0, 1)], pad)
svg.frame("mask-normal", R, R, [("ColorScheme-Background", 1, 0, None)])
svg.frame("hover", R, R, [("ColorScheme-ButtonHover", 0.9, 0, 1.2)], pad)
svg.frame("focus", R, R, [("ColorScheme-ButtonFocus", 1, 0, 1.6)], pad)
svg.frame("pressed", R, R, [("ColorScheme-Highlight", 1, 0, None), ("ColorScheme-ButtonFocus", 0.85, 0, 1.2)], pad)
svg.frame("toolbutton-hover", R, R, [("ColorScheme-Text", 0.08, 0, None)], pad)
svg.frame("toolbutton-focus", R, R, [("ColorScheme-ButtonFocus", 0.9, 0, 1.4)], pad)
svg.frame("toolbutton-pressed", R, R, [("ColorScheme-Highlight", 1, 0, None), ("ColorScheme-ButtonFocus", 0.85, 0, 1.2)], pad)
svg.frame("shadow", R, R, [], {"top-margin": 1, "bottom-margin": 1, "left-margin": 1, "right-margin": 1})
svg.element('<rect id="normal-hint-compose-over-border" x="0" y="0" width="2" height="2" style="fill:#000;fill-opacity:0"/>')
svg.element('<rect id="pressed-hint-compose-over-border" x="0" y="0" width="2" height="2" style="fill:#000;fill-opacity:0"/>')
svg.write("widgets/button.svgz")

# Open apps in the panel: a faint tile on hover, and for the active one a tile
# with a gold line along the panel edge.
svg = Svg()
R = 14
for edge in ("", "north-", "west-", "east-"):
    pad = {"left-margin": 6, "right-margin": 6, "top-margin": 6, "bottom-margin": 6}
    svg.frame(f"{edge}normal", R, R, [], pad)
    svg.frame(f"{edge}hover", R, R, [("ColorScheme-Text", 0.08, 0, None)], pad)
    svg.frame(f"{edge}attention", R, R, [("ColorScheme-NeutralText", 0.22, 0, None), ("ColorScheme-NeutralText", 0.9, 0, 1.4)], pad)
    svg.frame(f"{edge}minimized", R, R, [("ColorScheme-Text", 0.03, 0, None)], pad)
    svg.frame(f"{edge}progress", R, R, [("ColorScheme-ViewFocus", 0.30, 0, None)], pad)
    svg.frame(f"{edge}focus", R, R, [("ColorScheme-Text", 0.10, 0, None), ("ColorScheme-ViewFocus", 1, 0, 1.6)], pad)
svg.write("widgets/tasks.svgz")

meta = {
    "KPlugin": {
        "Authors": [{"Name": "Stiloria"}],
        "Category": "",
        "Description": "Warm glass and navy pills with a gold edge, for Stiloria Day and Stiloria Night",
        "EnabledByDefault": True,
        "Id": "stiloria",
        "License": "LGPL-2.0-or-later",
        "Name": "Stiloria",
        "Version": "1.0",
        "Website": "https://github.com/mslanden/stiloria",
    },
    "X-Plasma-API": "5.0",
}
(ROOT / "metadata.json").write_text(json.dumps(meta, indent=4) + "\n")
(ROOT / "plasmarc").write_text("""[AdaptiveTransparency]
enabled=true

[ContrastEffect]
enabled=true
contrast=0.85
intensity=1.05
saturation=1.3

[BlurBehindEffect]
enabled=true
""")
print("wrote", ROOT / "metadata.json", "and plasmarc")
