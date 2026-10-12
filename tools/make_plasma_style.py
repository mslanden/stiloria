"""Write the Stiloria Plasma style, in the Porcelain design: solid panels and
menus, quiet sunk hovers, a slate-tinted selection, ink focus rings, pill
fields and buttons.

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
.ColorScheme-Background { color:#f4f1ec; }
.ColorScheme-Text { color:#1d1b18; }
.ColorScheme-Highlight { color:#3e5869; }
.ColorScheme-ViewBackground { color:#fbfaf7; }
.ColorScheme-ViewText { color:#1d1b18; }
.ColorScheme-ViewFocus { color:#1d1b18; }
.ColorScheme-ViewHover { color:#857d71; }
.ColorScheme-ButtonBackground { color:#fbfaf7; }
.ColorScheme-ButtonFocus { color:#1d1b18; }
.ColorScheme-ButtonHover { color:#857d71; }
.ColorScheme-NeutralText { color:#8a5a10; }
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

    def frame(self, prefix, S, R, layers, hints=None, spacer=True, bar=None):
        """layers: (cls, opacity, outer inset, inner inset or None for a fill).
        bar: (side, cls, opacity, thickness, gap), a short mark along one side
        that stays between the corners however wide the frame is stretched."""
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
            if bar and part == bar[0]:
                side, cls, opacity, t, gap = bar
                x, y, w, h = {"bottom": (0, S - gap - t, E, t), "top": (0, gap, E, t),
                              "left": (gap, 0, t, E), "right": (S - gap - t, 0, t, E)}[side]
                items.append(self.shape(f"M{fmt(x0 + x)},{fmt(y0 + y)} h{fmt(w)} v{fmt(h)} h{fmt(-w)} Z", cls, opacity))
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
    """A soft shadow around a panel: radial at the corners, linear on the
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


def surface(rel, R, margin, shadow_size, shadow_strength, extra=None):
    """A Porcelain panel: a solid surface with a hairline edge and a soft shadow."""
    svg = Svg()
    S = R
    layers = [("ColorScheme-ViewBackground", 1, 1, None), ("ColorScheme-Text", 0.10, 0, 1)]
    hints = {"top-margin": margin, "bottom-margin": margin, "left-margin": margin, "right-margin": margin,
             "top-inset": 4, "bottom-inset": 4, "left-inset": 4, "right-inset": 4}
    svg.frame("", S, R, layers, hints)
    svg.frame("mask", S, R, [("ColorScheme-Background", 1, 0, None)])
    if extra:
        extra(svg, S, R, layers)
    shadow(svg, shadow_size, R, shadow_strength)
    svg.element('<rect id="hint-tile-center" x="0" y="0" width="5" height="5" style="fill:#000;fill-opacity:0"/>')
    svg.write(rel)


def thick(svg, S, R, layers):
    svg.frame("thick", S, R, layers, {"top-margin": 8, "bottom-margin": 8, "left-margin": 8, "right-margin": 8})


# Panels and menus are solid; Porcelain keeps frost for things you press.
# Plasma looks for translucent/, solid/ and opaque/ versions of these first
# (depending on blur, compositing and the panel's opacity setting) and takes
# Breeze's when a theme has none, so every variant gets the same solid surface.
for variant in ("", "translucent/", "solid/", "opaque/"):
    surface(f"{variant}dialogs/background.svgz", R=24, margin=12, shadow_size=30, shadow_strength=0.20)
    surface(f"{variant}widgets/panel-background.svgz", R=24, margin=6, shadow_size=24, shadow_strength=0.14, extra=thick)
    surface(f"{variant}widgets/tooltip.svgz", R=14, margin=8, shadow_size=18, shadow_strength=0.18)
    surface(f"{variant}widgets/background.svgz", R=24, margin=12, shadow_size=24, shadow_strength=0.14)

# List items (start menu, system tray, notification history). Plasma marks the
# current item with the "hover" frame and keeps the item's own text color, so
# the current item is a sunk well, as in Porcelain, and a selected (pressed)
# one takes the accent's soft tint.
svg = Svg()
R = 12  # at most half the shortest row (start menu rows are about 30px), or corners overlap
svg.frame("normal", R, R, [])
svg.frame("hover", R, R, [("ColorScheme-Text", 0.07, 0, None)])
svg.frame("selected", R, R, [("ColorScheme-Highlight", 0.16, 0, None)])
svg.frame("selected+hover", R, R, [("ColorScheme-Highlight", 0.22, 0, None)])
svg.element('<rect id="hint-tile-center" x="0" y="0" width="5" height="5" style="fill:#000;fill-opacity:0"/>')
svg.write("widgets/viewitem.svgz")

# Text fields: a sunk pill with no border; a faint ring on hover, and the 2px
# ink ring on focus. Fields are about 30px tall; corners taller than half that
# overlap, and the overlap shows as a darker line through the fill.
svg = Svg()
R = 14
pad = {"left-margin": 14, "right-margin": 14, "top-margin": 6, "bottom-margin": 6}
svg.frame("base", R, R, [("ColorScheme-Text", 0.07, 0, None)], pad)
svg.frame("hover", R, R, [("ColorScheme-Text", 0.28, 0, 1)], pad)
svg.frame("focus", R, R, [("ColorScheme-ViewFocus", 1, 0, 2)], pad)
svg.frame("focusframe", R, R, [("ColorScheme-ViewFocus", 1, 0, 2)], pad)
svg.element('<rect id="hint-focus-over-base" x="0" y="0" width="2" height="2" style="fill:#000;fill-opacity:0"/>')
svg.element('<rect id="hint-tile-center" x="0" y="0" width="5" height="5" style="fill:#000;fill-opacity:0"/>')
svg.write("widgets/lineedit.svgz")

# Buttons: frost pills (a faint fill and a fine rim) that thicken on hover and
# when pressed or checked; focus is the 2px ink ring. Tool buttons are ghosts.
svg = Svg()
R = 14  # as for fields: no more than half a button's height
pad = {"left-margin": 12, "right-margin": 12, "top-margin": 5, "bottom-margin": 5}
svg.frame("normal", R, R, [("ColorScheme-Text", 0.05, 1, None), ("ColorScheme-Text", 0.14, 0, 1)], pad)
svg.frame("mask-normal", R, R, [("ColorScheme-Background", 1, 0, None)])
svg.frame("hover", R, R, [("ColorScheme-Text", 0.05, 1, None), ("ColorScheme-Text", 0.24, 0, 1)], pad)
svg.frame("focus", R, R, [("ColorScheme-ButtonFocus", 1, 0, 2)], pad)
svg.frame("pressed", R, R, [("ColorScheme-Text", 0.14, 1, None), ("ColorScheme-Text", 0.20, 0, 1)], pad)
svg.frame("toolbutton-hover", R, R, [("ColorScheme-Text", 0.07, 0, None)], pad)
svg.frame("toolbutton-focus", R, R, [("ColorScheme-ButtonFocus", 1, 0, 2)], pad)
svg.frame("toolbutton-pressed", R, R, [("ColorScheme-Text", 0.13, 0, None)], pad)
svg.frame("shadow", R, R, [], {"top-margin": 1, "bottom-margin": 1, "left-margin": 1, "right-margin": 1})
svg.element('<rect id="normal-hint-compose-over-border" x="0" y="0" width="2" height="2" style="fill:#000;fill-opacity:0"/>')
svg.element('<rect id="pressed-hint-compose-over-border" x="0" y="0" width="2" height="2" style="fill:#000;fill-opacity:0"/>')
svg.write("widgets/button.svgz")

# Open apps in the panel: a sunk tile on hover, and for the active one a sunk
# tile with a short slate mark along the panel's screen edge.
svg = Svg()
R = 14
for edge, side in (("", "bottom"), ("north-", "top"), ("west-", "left"), ("east-", "right")):
    pad = {"left-margin": 6, "right-margin": 6, "top-margin": 6, "bottom-margin": 6}
    svg.frame(f"{edge}normal", R, R, [], pad)
    svg.frame(f"{edge}hover", R, R, [("ColorScheme-Text", 0.07, 0, None)], pad)
    svg.frame(f"{edge}attention", R, R, [("ColorScheme-NeutralText", 0.18, 0, None)], pad,
              bar=(side, "ColorScheme-NeutralText", 1, 3, 2))
    svg.frame(f"{edge}minimized", R, R, [("ColorScheme-Text", 0.03, 0, None)], pad)
    svg.frame(f"{edge}progress", R, R, [("ColorScheme-Highlight", 0.22, 0, None)], pad)
    svg.frame(f"{edge}focus", R, R, [("ColorScheme-Text", 0.07, 0, None)], pad,
              bar=(side, "ColorScheme-Highlight", 1, 3, 2))
svg.write("widgets/tasks.svgz")

meta = {
    "KPlugin": {
        "Authors": [{"Name": "Stiloria"}],
        "Category": "",
        "Description": "Porcelain: solid ivory or warm-black panels, ink text and one slate accent, for Stiloria Day and Stiloria Night",
        "EnabledByDefault": True,
        "Id": "stiloria",
        "License": "LGPL-2.0-or-later",
        "Name": "Stiloria",
        "Version": "2.0",
        "Website": "https://github.com/mslanden/stiloria",
    },
    "X-Plasma-API": "5.0",
}
(ROOT / "metadata.json").write_text(json.dumps(meta, indent=4) + "\n")
# Solid panels: no translucent variants, and no blur or contrast behind them.
(ROOT / "plasmarc").write_text("""[AdaptiveTransparency]
enabled=false

[ContrastEffect]
enabled=false

[BlurBehindEffect]
enabled=false
""")
print("wrote", ROOT / "metadata.json", "and plasmarc")
