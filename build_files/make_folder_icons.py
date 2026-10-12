"""Make Stiloria's icon themes: Breeze with Porcelain's stone folders.

usage: python3 make_folder_icons.py [output dir]   (default /usr/share/icons)

Breeze fills its large folder icons (places at 32-96 px; the 16-24 px ones
are outlines in the text color) with the accent color, which in Stiloria is
slate. Porcelain's folders are stone, so Stiloria (for Stiloria Day) and
Stiloria-Dark (for Stiloria Night) inherit Breeze and Breeze Dark and replace
only those icons: the accent fill becomes stone and the shade on the folder's
back panel lighter, while emblems (the documents page, the music note) keep
the text color. Links elsewhere in Breeze that resolve to these icons, such
as mimetypes/64/inode-directory.svg, are copied too, so a folder is stone
wherever it is looked up. The themes are built from the image's own Breeze
during the build, so they follow its updates.
"""
import os, pathlib, re, subprocess, sys

ICONS = pathlib.Path("/usr/share/icons")
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ICONS
SIZES = ("32", "48", "64", "96")
# Theme: (base theme, display name, stone, back panel shade, description)
THEMES = {
    "Stiloria": ("breeze", "Stiloria", "#cfc6b8", "0.13",
                 "Breeze with Porcelain's stone folders, for Stiloria Day"),
    "Stiloria-Dark": ("breeze-dark", "Stiloria Dark", "#45403a", "0.26",
                      "Breeze Dark with Porcelain's stone folders, for Stiloria Night"),
}
TAG = re.compile(r"<[A-Za-z][^<>]*>")
SHADE = re.compile(r"fill-opacity:\s*0?\.33\b")


def recolor(svg, stone, shade):
    """Stone for every shape filled with the accent, and a lighter shade for
    the unfilled (black) 33% overlay Breeze darkens the back panel with."""
    accents = 0

    def fix(match):
        nonlocal accents
        tag = match.group(0)
        if 'class="ColorScheme-Accent"' in tag:
            accents += 1
            tag = tag.replace(' class="ColorScheme-Accent"', "").replace('class="ColorScheme-Accent"', "")
            if "currentColor" in tag:
                return tag.replace("currentColor", stone)
            if 'style="' in tag:
                return tag.replace('style="', f'style="fill:{stone};', 1)
            return re.sub(r"^<(\w+)", rf'<\1 style="fill:{stone}"', tag)
        if SHADE.search(tag) and "class=" not in tag and " fill=" not in tag and "fill:" not in tag:
            return SHADE.sub(f"fill-opacity:{shade}", tag)
        return tag

    return TAG.sub(fix, svg), accents


def sections(index):
    """The [Icon Theme] header's lines and each directory's section, from an index.theme."""
    header, dirs, current = [], {}, None
    for line in index.read_text().splitlines():
        if line.startswith("["):
            current = line.strip("[]")
            if current != "Icon Theme":
                dirs[current] = [line]
            continue
        if current == "Icon Theme":
            header.append(line)
        elif current and line.strip() and not line.startswith("#"):
            dirs[current].append(line)
    return header, dirs


for name, (base, display, stone, shade, comment) in THEMES.items():
    src, dst = ICONS / base, OUT / name
    made, dirs = set(), []
    for size in SIZES:
        rel_dir = f"places/{size}"
        files = sorted((src / rel_dir).glob("*.svg"))
        # Only icons that fill a shape with the accent; folders with a color of
        # their own (folder-red, folder-android's green) only name it in their
        # stylesheet and stay as they are.
        recolored = {f.name for f in files if 'class="ColorScheme-Accent"' in f.resolve().read_text()}
        (dst / rel_dir).mkdir(parents=True, exist_ok=True)
        for f in files:
            if f.name not in recolored:
                continue
            target = dst / rel_dir / f.name
            target.unlink(missing_ok=True)
            link = os.readlink(f) if f.is_symlink() else None
            if link and "/" not in link and link in recolored:
                os.symlink(link, target)  # a link to another icon in this folder, kept as a link
            else:
                text, accents = recolor(f.resolve().read_text(), stone, shade)
                assert accents, f
                target.write_text(text)
            made.add(f.resolve())
        dirs.append(rel_dir)
    # Links from other folders of the theme into the recolored icons.
    for root, _, names in os.walk(src):
        rel_root = pathlib.Path(root).relative_to(src)
        if rel_root.parts[:1] == ("places",) and rel_root.name in SIZES:
            continue
        for n in names:
            path = pathlib.Path(root) / n
            if path.is_symlink() and path.resolve() in made:
                (dst / rel_root).mkdir(parents=True, exist_ok=True)
                (dst / rel_root / n).unlink(missing_ok=True)
                os.symlink(os.readlink(path), dst / rel_root / n)
                if str(rel_root) not in dirs:
                    dirs.append(str(rel_root))
    header, base_dirs = sections(src / "index.theme")
    keep = [line for line in header if re.match(r"(DisplayDepth|Example|FollowsColorScheme|KDE-Extensions|\w+(Default|Sizes))=", line)]
    index = ["[Icon Theme]", f"Name={display}", f"Comment={comment}", f"Inherits={base},hicolor", *keep,
             f"Directories={','.join(dirs)}", ""]
    for d in dirs:
        index += base_dirs[d] + [""]
    (dst / "index.theme").write_text("\n".join(index))
    for size in SIZES:
        assert (dst / f"places/{size}/folder.svg").exists(), (name, size)
    subprocess.run(["gtk-update-icon-cache", "-q", "-f", "-t", str(dst)], check=True)
    count = sum(1 for d in dirs for _ in (dst / d).iterdir())
    print(f"{name}: {count} icons in {len(dirs)} folders, stone {stone}")
