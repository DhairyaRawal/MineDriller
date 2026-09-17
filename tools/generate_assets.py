"""
MineDriller asset generator.
Generates every texture (PNG) and sound (WAV) used by the game so the
project has zero external asset dependencies. Deterministic (fixed seed).

Run from the project root:  python tools/generate_assets.py
"""
import math
import os
import random
import struct
import wave

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "textures")
AUD = os.path.join(ROOT, "assets", "audio")
os.makedirs(TEX, exist_ok=True)
os.makedirs(AUD, exist_ok=True)

rng = random.Random(20260720)

TILE = 64

# ---------------------------------------------------------------- textures

LAYER_SOFT = [
    (138, 90, 51),    # L1 crust - earthy brown
    (154, 74, 46),    # L2 upper mantle - terracotta
    (125, 59, 62),    # L3 lower mantle - maroon
    (88, 64, 110),    # L4 upper core - violet
    (60, 46, 46),     # L5 core - charred
]
LAYER_HARD = [
    (94, 62, 38),
    (108, 50, 32),
    (86, 40, 44),
    (60, 44, 78),
    (40, 30, 30),
]
ORE_COLORS = {
    "iron":    (156, 139, 122),
    "silver":  (207, 214, 221),
    "gold":    (242, 193, 78),
    "emerald": (62, 203, 113),
    "ruby":    (232, 57, 90),
    "opal":    (170, 120, 255),
}

# Layer-specific theme colors for modern, depth-aware visuals
LAYER_THEMES = [
    {"bg": (138, 90, 51),   "glow": (200, 150, 100), "accent": (255, 200, 100)},  # L1 warm browns
    {"bg": (154, 74, 46),   "glow": (220, 120, 80),  "accent": (255, 150, 80)},   # L2 warm reds
    {"bg": (125, 59, 62),   "glow": (200, 100, 100), "accent": (255, 100, 120)},  # L3 deep reds
    {"bg": (88, 64, 110),   "glow": (160, 120, 200), "accent": (200, 150, 255)},  # L4 purples
    {"bg": (60, 46, 46),    "glow": (140, 100, 100), "accent": (200, 100, 100)},  # L5 blacks/grays
]

DRILL_SKINS = [
    {"name": "standard", "color": (232, 130, 36), "trim": (118, 58, 12)},
    {"name": "elite",    "color": (238, 196, 60), "trim": (150, 108, 16),
     "glass": (255, 236, 170)},
    {"name": "deep",     "color": (150, 92, 190), "trim": (78, 40, 116),
     "glass": (206, 170, 255)},
    {"name": "glacier",  "color": (74, 164, 224), "trim": (28, 88, 148),
     "glass": (198, 244, 255)},
    {"name": "inferno",  "color": (222, 76, 54),  "trim": (128, 26, 18),
     "glass": (255, 198, 150)},
]


def clamp(v):
    return max(0, min(255, int(v)))


def lerp(a, b, t):
    return a + (b - a) * t


# --------------------------------------------------------- seamless noise
#
# Terrain is drawn by stamping these 64px tiles edge to edge across whole
# chunks. Any texture that does not wrap produces a visible grid, which is
# exactly the "grid block" look we are trying to kill -- so all rock texture
# comes from value noise sampled on a torus, which tiles perfectly.

_noise_cache = {}


def tileable_noise(size, period, seed_offset, octaves=4):
    """Value noise that wraps seamlessly across `size` pixels."""
    key = (size, period, seed_offset, octaves)
    if key in _noise_cache:
        return _noise_cache[key]

    rnd = random.Random(9871 + seed_offset * 131)
    out = [[0.0] * size for _ in range(size)]
    amp, total, p = 1.0, 0.0, period

    for _ in range(octaves):
        grid = [[rnd.random() for _ in range(p)] for _ in range(p)]
        for y in range(size):
            fy = y / size * p
            iy = int(fy)
            ty = fy - iy
            ty = ty * ty * (3 - 2 * ty)          # smoothstep
            y0, y1 = iy % p, (iy + 1) % p
            for x in range(size):
                fx = x / size * p
                ix = int(fx)
                tx = fx - ix
                tx = tx * tx * (3 - 2 * tx)
                x0, x1 = ix % p, (ix + 1) % p
                top = lerp(grid[y0][x0], grid[y0][x1], tx)
                bot = lerp(grid[y1][x0], grid[y1][x1], tx)
                out[y][x] += lerp(top, bot, ty) * amp
        total += amp
        amp *= 0.5
        p *= 2

    for y in range(size):
        for x in range(size):
            out[y][x] /= total

    _noise_cache[key] = out
    return out


def tint(base, t, lo=-38, hi=34):
    """Shift a base colour along a noise value in [0,1]."""
    d = lo + (hi - lo) * t
    return (clamp(base[0] + d), clamp(base[1] + d), clamp(base[2] + d), 255)


def rock_field(img, base, x0, y0, seed_offset, contrast=1.0, warp=0.0):
    """Fill one 64px tile with seamless mottled rock."""
    n1 = tileable_noise(TILE, 4, seed_offset)
    n2 = tileable_noise(TILE, 8, seed_offset + 7)
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            v = n1[y][x] * 0.65 + n2[y][x] * 0.35
            v = 0.5 + (v - 0.5) * contrast
            if warp:
                v += (n2[(y + 17) % TILE][(x + 29) % TILE] - 0.5) * warp
            px[x0 + x, y0 + y] = tint(base, max(0.0, min(1.0, v)))


def mineral_veins(img, base, x0, y0, seed_offset, strength=0.55, threshold=0.62):
    """Ridged noise -> thin bright veins. Wraps with the underlying noise."""
    n = tileable_noise(TILE, 6, seed_offset + 23)
    px = img.load()
    light = (clamp(base[0] + 60), clamp(base[1] + 54), clamp(base[2] + 46))
    for y in range(TILE):
        for x in range(TILE):
            ridge = 1.0 - abs(n[y][x] * 2.0 - 1.0)
            if ridge <= threshold:
                continue
            k = (ridge - threshold) / (1.0 - threshold) * strength
            cur = px[x0 + x, y0 + y]
            px[x0 + x, y0 + y] = (
                clamp(lerp(cur[0], light[0], k)),
                clamp(lerp(cur[1], light[1], k)),
                clamp(lerp(cur[2], light[2], k)),
                255,
            )


def crystalline(img, base, x0, y0, seed_offset, count=26):
    """Dense angular inclusions that read as 'this rock is harder'."""
    r = random.Random(4400 + seed_offset)
    d = ImageDraw.Draw(img)
    dark = (clamp(base[0] - 42), clamp(base[1] - 40), clamp(base[2] - 36), 255)
    lite = (clamp(base[0] + 46), clamp(base[1] + 44), clamp(base[2] + 42), 255)
    for _ in range(count):
        cx = x0 + r.randrange(TILE)
        cy = y0 + r.randrange(TILE)
        s = r.randrange(3, 7)
        pts = [(cx, cy - s), (cx + s, cy), (cx, cy + s), (cx - s, cy)]
        d.polygon(pts, fill=dark)
        d.polygon([(cx, cy - s), (cx + s, cy), (cx, cy)], fill=lite)


def crust_edges(img, x0, y0, crust, width_px=8, strength=0.92, power=1.5):
    """Darken a tile toward `crust` near its borders.

    Used for magma and water, which are whole-cell materials and would
    otherwise tile out as flat, hard-edged bright squares. Fading the rim to a
    dark crust makes isolated cells read as pools and adjacent cells merge into
    a continuous flow.
    """
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            e = min(x, y, TILE - 1 - x, TILE - 1 - y)
            if e >= width_px:
                continue
            k = ((1.0 - e / width_px) ** power) * strength
            cur = px[x0 + x, y0 + y]
            px[x0 + x, y0 + y] = (
                clamp(lerp(cur[0], crust[0], k)),
                clamp(lerp(cur[1], crust[1], k)),
                clamp(lerp(cur[2], crust[2], k)),
                255,
            )


def gem(d, color, cx, cy, s):
    """One faceted gem: dark body, lit facet, specular pip."""
    body = (*color, 255)
    dark = (clamp(color[0] * 0.55), clamp(color[1] * 0.55), clamp(color[2] * 0.55), 255)
    lite = (clamp(color[0] + 78), clamp(color[1] + 78), clamp(color[2] + 78), 255)
    d.polygon([(cx, cy - s), (cx + s, cy), (cx, cy + s), (cx - s, cy)], fill=dark)
    d.polygon([(cx, cy - s), (cx + s, cy), (cx, cy)], fill=body)
    d.polygon([(cx, cy - s), (cx, cy), (cx - s, cy)], fill=lite)
    d.ellipse((cx - s * 0.28, cy - s * 0.55, cx + s * 0.12, cy - s * 0.15),
              fill=(255, 255, 255, 210))


def gem_overlay(img, color, x0, y0, seed_offset, count=3):
    """Gems on a TRANSPARENT tile.

    The world blends this over whichever layer's rock the ore sits in, so ore
    never paints its own background square -- it reads as gems embedded in the
    surrounding stone instead of a stamped tile.
    """
    r = random.Random(7700 + seed_offset)
    glow = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    spots = []
    for _ in range(count):
        cx = r.randrange(16, TILE - 16)
        cy = r.randrange(16, TILE - 16)
        s = r.randrange(7, 11)
        spots.append((cx, cy, s))
        for rad in range(int(s * 2.4), 0, -1):
            a = int(52 * (1 - rad / (s * 2.4)) ** 2)
            gd.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=(*color, a))
    for cx, cy, s in spots:
        gem(gd, color, cx, cy, s)
    img.alpha_composite(glow, (x0, y0))


def build_tile_atlas():
    cols, rows = 8, 3
    img = Image.new("RGBA", (cols * TILE, rows * TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def fill(cx, cy, color):
        d.rectangle((cx * TILE, cy * TILE, cx * TILE + TILE - 1, cy * TILE + TILE - 1),
                    fill=(*color, 255))

    # Row 0: soft ground per layer (0-4), bedrock (5), grass (6), chest (7)
    # Low contrast on purpose: the shader adds per-cell brightness jitter, so
    # the texture only has to supply fine grain. High-contrast blobs here would
    # read as a repeating pattern once tiled across a chunk.
    for i, c in enumerate(LAYER_SOFT):
        rock_field(img, c, i * TILE, 0, seed_offset=i, contrast=0.42)
        mineral_veins(img, c, i * TILE, 0, seed_offset=i, strength=0.16,
                      threshold=0.70)

    bed = (36, 34, 42)
    rock_field(img, bed, 5 * TILE, 0, seed_offset=51, contrast=1.25)
    crystalline(img, bed, 5 * TILE, 0, seed_offset=51, count=34)

    # Grass: soil body with a turf crown, blended so the join is not a hard line.
    soil = (118, 80, 45)
    rock_field(img, soil, 6 * TILE, 0, seed_offset=61, contrast=0.9)
    turf = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    rock_field(turf, (78, 158, 66), 0, 0, seed_offset=62, contrast=1.1)
    # Ragged turf edge with scattered blades below it, so the soil/grass join
    # is a broken line rather than a painted stripe.
    mask = Image.new("L", (TILE, TILE), 0)
    md = ImageDraw.Draw(mask)
    tn = tileable_noise(TILE, 4, 63)
    gr = random.Random(6301)
    for x in range(TILE):
        edge = 9 + int(tn[0][x] * 16)
        md.rectangle((x, 0, x, edge), fill=255)
        for _ in range(2):
            blade = edge + gr.randrange(1, 9)
            if blade < TILE:
                md.rectangle((x, blade, x, blade + gr.randrange(1, 3)),
                             fill=gr.randrange(90, 200))
    img.paste(turf, (6 * TILE, 0), mask)

    # Chest
    fill(7, 0, (48, 37, 32))
    rock_field(img, (48, 37, 32), 7 * TILE, 0, seed_offset=71, contrast=0.7)
    d.rounded_rectangle((7 * TILE + 9, 21, 7 * TILE + TILE - 9, TILE - 9),
                        radius=4, fill=(150, 100, 38, 255), outline=(84, 52, 16, 255), width=2)
    d.rectangle((7 * TILE + 9, 21, 7 * TILE + TILE - 9, 35), fill=(196, 142, 62, 255))
    d.rectangle((7 * TILE + 9, 34, 7 * TILE + TILE - 9, 37), fill=(84, 52, 16, 255))
    d.rectangle((7 * TILE + 28, 30, 7 * TILE + 36, 44), fill=(250, 212, 92, 255))
    d.ellipse((7 * TILE + 30, 36, 7 * TILE + 34, 40), fill=(120, 84, 20, 255))

    # Row 1: hard rock per layer (0-4), magma (5), water (6), spare dark (7)
    #
    # Hard rock stays in the SAME colour family as the layer's soft rock and is
    # distinguished by dense crystal inclusions plus a slight darkening. If it
    # were a different hue it would tile out as obvious coloured squares.
    for i, c in enumerate(LAYER_HARD):
        rock_field(img, c, i * TILE, TILE, seed_offset=100 + i, contrast=0.55)
        crystalline(img, c, i * TILE, TILE, seed_offset=100 + i, count=16)
        mineral_veins(img, c, i * TILE, TILE, seed_offset=100 + i,
                      strength=0.28, threshold=0.62)

    # Magma: hot noise ramped through black -> red -> orange -> yellow.
    mn = tileable_noise(TILE, 5, 201)
    mpx = img.load()
    for y in range(TILE):
        for x in range(TILE):
            v = mn[y][x]
            if v < 0.45:
                col = (int(lerp(90, 190, v / 0.45)), int(lerp(18, 52, v / 0.45)), 14)
            elif v < 0.72:
                t = (v - 0.45) / 0.27
                col = (int(lerp(190, 244, t)), int(lerp(52, 138, t)), int(lerp(14, 30, t)))
            else:
                t = (v - 0.72) / 0.28
                col = (int(lerp(244, 255, t)), int(lerp(138, 226, t)), int(lerp(30, 120, t)))
            mpx[5 * TILE + x, TILE + y] = (*col, 255)

    # Water: layered blue with caustic highlights.
    wn = tileable_noise(TILE, 6, 211)
    for y in range(TILE):
        for x in range(TILE):
            v = wn[y][x]
            col = (int(lerp(28, 74, v)), int(lerp(84, 148, v)), int(lerp(150, 210, v)))
            mpx[6 * TILE + x, TILE + y] = (*col, 255)
    for y in range(TILE):
        for x in range(TILE):
            c = 1.0 - abs(wn[y][x] * 2.0 - 1.0)
            if c > 0.80:
                k = (c - 0.80) / 0.20
                cur = mpx[6 * TILE + x, TILE + y]
                mpx[6 * TILE + x, TILE + y] = (
                    clamp(lerp(cur[0], 190, k)), clamp(lerp(cur[1], 228, k)),
                    clamp(lerp(cur[2], 255, k)), 255)

    crust_edges(img, 5 * TILE, TILE, (46, 16, 12))     # magma: cooled crust
    crust_edges(img, 6 * TILE, TILE, (10, 30, 58))     # water: deep shadow

    fill(7, 1, (24, 22, 26))

    # Row 2: ore OVERLAYS on transparent tiles (blended over layer rock in-game)
    for i, (_name, color) in enumerate(ORE_COLORS.items()):
        gem_overlay(img, color, i * TILE, 2 * TILE, seed_offset=300 + i, count=3)
    gem_overlay(img, (150, 240, 255), 6 * TILE, 2 * TILE, seed_offset=340, count=4)
    fill(7, 2, (24, 22, 26))

    img.save(os.path.join(TEX, "tiles.png"))


def draw_pod(d, body, trim, glass=(150, 214, 250)):
    """Shared drill-pod artwork so every skin is the same machine, recoloured."""
    shade = (clamp(body[0] * 0.72), clamp(body[1] * 0.72), clamp(body[2] * 0.72))
    lite = (clamp(body[0] + 46), clamp(body[1] + 46), clamp(body[2] + 46))

    # drop shadow anchors the pod against terrain
    d.ellipse((14, 52, 50, 60), fill=(0, 0, 0, 70))

    # chassis
    d.rounded_rectangle((9, 7, 55, 43), radius=11, fill=(*shade, 255),
                        outline=(*trim, 255), width=3)
    d.rounded_rectangle((9, 7, 55, 30), radius=11, fill=(*body, 255))
    d.rounded_rectangle((13, 10, 51, 18), radius=6, fill=(*lite, 255))   # top highlight

    # side vents
    for vy in (33, 37):
        d.rectangle((14, vy, 22, vy + 2), fill=(*trim, 255))
        d.rectangle((42, vy, 50, vy + 2), fill=(*trim, 255))

    # canopy
    d.ellipse((20, 13, 44, 33), fill=(*trim, 255))
    d.ellipse((22, 15, 42, 31), fill=(*glass, 255))
    d.ellipse((25, 17, 34, 24), fill=(232, 250, 255, 235))
    d.ellipse((27, 19, 31, 22), fill=(255, 255, 255, 255))

    # treads
    d.rounded_rectangle((6, 39, 58, 50), radius=5, fill=(52, 52, 60, 255))
    for x in range(10, 56, 8):
        d.ellipse((x, 41, x + 6, 47), fill=(126, 126, 138, 255))
        d.ellipse((x + 1, 42, x + 4, 45), fill=(74, 74, 84, 255))

    # drill bit: cone + spiral flutes
    d.polygon([(21, 49), (43, 49), (32, 63)], fill=(206, 210, 220, 255))
    d.polygon([(21, 49), (32, 49), (32, 63)], fill=(154, 158, 170, 255))
    for i, yy in enumerate((52, 56, 59)):
        inset = 3 + i * 3
        d.line((21 + inset, yy, 43 - inset, yy - 2), fill=(96, 100, 112, 255), width=1)
    d.polygon([(21, 47), (43, 47), (43, 50), (21, 50)], fill=(*trim, 255))


def build_player():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw_pod(ImageDraw.Draw(img), (232, 130, 36), (118, 58, 12))
    img.save(os.path.join(TEX, "player.png"))


def build_crawly():
    s = 48
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((10, 14, 38, 40), fill=(120, 40, 150, 255), outline=(60, 16, 80, 255), width=2)
    for i in range(4):
        x = 12 + i * 8
        d.line((x, 36, x - 4, 46), fill=(60, 16, 80, 255), width=3)
        d.line((x + 4, 36, x + 8, 46), fill=(60, 16, 80, 255), width=3)
    d.ellipse((16, 20, 24, 28), fill=(255, 220, 60, 255))
    d.ellipse((26, 20, 34, 28), fill=(255, 220, 60, 255))
    d.ellipse((19, 23, 22, 26), fill=(20, 10, 20, 255))
    d.ellipse((29, 23, 32, 26), fill=(20, 10, 20, 255))
    img.save(os.path.join(TEX, "crawly.png"))


def build_zombie():
    img = Image.new("RGBA", (48, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((16, 20, 32, 46), fill=(96, 140, 70, 255))       # torso
    d.ellipse((14, 4, 34, 24), fill=(130, 170, 96, 255))         # head
    d.rectangle((18, 10, 23, 15), fill=(240, 240, 220, 255))     # eyes
    d.rectangle((26, 10, 31, 15), fill=(200, 60, 60, 255))
    d.rectangle((10, 22, 16, 40), fill=(96, 140, 70, 255))       # arms out
    d.rectangle((32, 22, 38, 40), fill=(96, 140, 70, 255))
    d.rectangle((17, 46, 23, 62), fill=(70, 90, 60, 255))        # legs
    d.rectangle((25, 46, 31, 62), fill=(70, 90, 60, 255))
    # miner helmet
    d.rectangle((14, 2, 34, 8), fill=(220, 190, 60, 255))
    d.ellipse((21, 0, 27, 6), fill=(250, 250, 200, 255))
    img.save(os.path.join(TEX, "zombie.png"))


def build_govt():
    s = 64
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((8, 12, 56, 44), radius=8, fill=(90, 100, 116, 255),
                        outline=(40, 46, 58, 255), width=3)
    d.rectangle((16, 18, 48, 30), fill=(50, 56, 70, 255))
    d.rectangle((18, 20, 30, 28), fill=(255, 80, 70, 255))      # siren window
    d.rounded_rectangle((6, 40, 58, 50), radius=5, fill=(40, 44, 52, 255))
    for x in range(10, 56, 9):
        d.ellipse((x, 42, x + 7, 49), fill=(90, 96, 108, 255))
    d.polygon([(56, 16), (63, 28), (56, 40)], fill=(190, 195, 205, 255))  # side drill
    d.rectangle((26, 6, 38, 12), fill=(200, 40, 40, 255))       # beacon
    img.save(os.path.join(TEX, "govt.png"))


def build_drill_skins():
    """Cosmetic drill variants: same machine, different paint."""
    for skin in DRILL_SKINS:
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        draw_pod(ImageDraw.Draw(img), skin["color"], skin["trim"],
                 skin.get("glass", (150, 214, 250)))
        img.save(os.path.join(TEX, f"player_{skin['name']}.png"))


def build_enemy_variants():
    """Elite and mini-boss variants of existing enemies."""
    # elite crawly (larger, brighter colors)
    s = 64
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((8, 12, 56, 52), fill=(180, 80, 220, 255), outline=(120, 40, 160, 255), width=3)
    for i in range(5):
        x = 10 + i * 10
        d.line((x, 50, x - 6, 62), fill=(120, 40, 160, 255), width=4)
        d.line((x + 4, 50, x + 10, 62), fill=(120, 40, 160, 255), width=4)
    d.ellipse((14, 18, 26, 30), fill=(255, 255, 100, 255))
    d.ellipse((38, 18, 50, 30), fill=(255, 255, 100, 255))
    d.ellipse((17, 22, 21, 27), fill=(20, 10, 20, 255))
    d.ellipse((43, 22, 47, 27), fill=(20, 10, 20, 255))
    d.ellipse((28, 25, 36, 35), fill=(255, 200, 100, 255))  # crown
    img.save(os.path.join(TEX, "crawly_elite.png"))

    # elite zombie (taller, darker, more threatening)
    img = Image.new("RGBA", (48, 80), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((14, 24, 34, 54), fill=(56, 80, 40, 255))  # torso
    d.ellipse((12, 2, 36, 26), fill=(80, 110, 60, 255))    # head
    d.rectangle((16, 8, 22, 16), fill=(255, 100, 100, 255))  # red eyes
    d.rectangle((26, 8, 32, 16), fill=(255, 100, 100, 255))
    d.rectangle((8, 26, 14, 48), fill=(56, 80, 40, 255))   # arms
    d.rectangle((34, 26, 40, 48), fill=(56, 80, 40, 255))
    d.rectangle((15, 54, 22, 78), fill=(40, 60, 35, 255))  # legs
    d.rectangle((26, 54, 33, 78), fill=(40, 60, 35, 255))
    # helmet
    d.rectangle((12, 0, 36, 8), fill=(200, 150, 40, 255))
    d.ellipse((20, -2, 28, 6), fill=(240, 220, 150, 255))
    img.save(os.path.join(TEX, "zombie_elite.png"))

    # mini-boss: plasma driller (fast govt variant)
    s = 80
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((12, 16, 68, 56), radius=12, fill=(140, 100, 180, 255),
                        outline=(100, 60, 140, 255), width=4)
    d.rectangle((22, 24, 58, 40), fill=(80, 50, 120, 255))
    d.rectangle((26, 26, 40, 38), fill=(255, 100, 200, 255))  # plasma core
    d.rounded_rectangle((10, 52, 70, 64), radius=6, fill=(80, 60, 100, 255))
    for x in range(16, 68, 11):
        d.ellipse((x, 54, x + 8, 62), fill=(140, 110, 160, 255))
    # dual drill
    d.polygon([(68, 20), (80, 32), (68, 44)], fill=(220, 150, 100, 255))
    d.polygon([(12, 20), (0, 32), (12, 44)], fill=(220, 150, 100, 255))
    d.rectangle((34, 8, 46, 16), fill=(255, 100, 100, 255))  # beacon
    img.save(os.path.join(TEX, "govt_boss.png"))


def build_new_enemies():
    """Three threats that each attack a DIFFERENT resource, so the player has
    to counter them in different ways rather than just avoiding contact."""

    # --- Magma Slug: slow, tanky, cooks your drill (attacks HEAT) ---
    img = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((6, 44, 58, 48), fill=(0, 0, 0, 70))
    d.ellipse((4, 16, 60, 46), fill=(148, 40, 18, 255))
    d.ellipse((8, 18, 52, 40), fill=(214, 78, 24, 255))
    d.ellipse((14, 20, 44, 34), fill=(255, 148, 42, 255))
    for i, bx in enumerate((18, 30, 42)):
        r = 5 - i
        d.ellipse((bx - r, 14 - r, bx + r, 14 + r), fill=(255, 206, 96, 220))
    d.ellipse((44, 22, 54, 32), fill=(255, 240, 190, 255))
    d.ellipse((47, 25, 51, 29), fill=(60, 16, 8, 255))
    for dx in (12, 24, 36):
        d.polygon([(dx, 18), (dx + 5, 8), (dx + 10, 18)], fill=(255, 172, 60, 255))
    img.save(os.path.join(TEX, "magma_slug.png"))

    # --- Crystal Bat: fast, erratic flyer (attacks HULL, hard to dodge) ---
    img = Image.new("RGBA", (56, 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(28, 20), (4, 6), (10, 24), (2, 22)], fill=(120, 96, 196, 255))
    d.polygon([(28, 20), (52, 6), (46, 24), (54, 22)], fill=(120, 96, 196, 255))
    d.polygon([(28, 20), (8, 10), (14, 22)], fill=(166, 142, 236, 255))
    d.polygon([(28, 20), (48, 10), (42, 22)], fill=(166, 142, 236, 255))
    d.ellipse((20, 12, 36, 30), fill=(58, 44, 94, 255))
    d.polygon([(24, 12), (28, 2), (32, 12)], fill=(58, 44, 94, 255))
    for cx, cy, s in ((28, 8, 4), (22, 18, 3), (34, 18, 3)):
        gem(d, (168, 234, 255), cx, cy, s)
    d.ellipse((22, 17, 27, 22), fill=(255, 236, 120, 255))
    d.ellipse((29, 17, 34, 22), fill=(255, 236, 120, 255))
    img.save(os.path.join(TEX, "crystal_bat.png"))

    # --- Rock Golem: heavy, guards ore (attacks TIME and route) ---
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((8, 58, 56, 64), fill=(0, 0, 0, 70))
    d.rounded_rectangle((12, 20, 52, 58), radius=8, fill=(74, 68, 62, 255))
    d.rounded_rectangle((12, 20, 32, 58), radius=8, fill=(96, 88, 80, 255))
    d.rounded_rectangle((18, 8, 46, 28), radius=6, fill=(110, 100, 90, 255))
    d.rounded_rectangle((6, 26, 18, 50), radius=5, fill=(88, 80, 72, 255))
    d.rounded_rectangle((46, 26, 58, 50), radius=5, fill=(88, 80, 72, 255))
    d.ellipse((22, 14, 30, 22), fill=(120, 240, 170, 255))
    d.ellipse((34, 14, 42, 22), fill=(120, 240, 170, 255))
    for cx, cy, s in ((22, 34, 5), (38, 44, 4), (30, 26, 3)):
        gem(d, (86, 214, 140), cx, cy, s)
    for _ in range(10):
        rx = rng.randrange(14, 50)
        ry = rng.randrange(24, 56)
        d.point((rx, ry), fill=(46, 42, 38, 255))
    img.save(os.path.join(TEX, "rock_golem.png"))


def build_upgrade_icons():
    """64x64 icons for the seven shop upgrade tracks."""
    def canvas():
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        return img, ImageDraw.Draw(img)

    # drill_speed: drill cone with speed lines
    img, d = canvas()
    d.polygon([(20, 8), (44, 8), (32, 56)], fill=(200, 205, 215, 255))
    d.polygon([(26, 8), (32, 8), (32, 44)], fill=(150, 155, 168, 255))
    for y in (16, 26, 36):
        d.line((6, y, 16, y), fill=(240, 180, 60, 255), width=3)
        d.line((48, y, 58, y), fill=(240, 180, 60, 255), width=3)
    img.save(os.path.join(TEX, "icon_drill_speed.png"))

    # drill_bit: bit tip with gem edge
    img, d = canvas()
    d.polygon([(16, 10), (48, 10), (32, 54)], fill=(120, 126, 140, 255))
    d.polygon([(24, 10), (40, 10), (32, 32)], fill=(90, 96, 110, 255))
    d.polygon([(32, 40), (40, 48), (32, 56), (24, 48)], fill=(80, 220, 230, 255))
    img.save(os.path.join(TEX, "icon_drill_bit.png"))

    # cooling: snowflake
    img, d = canvas()
    for ang in range(6):
        a = math.pi / 3 * ang
        x2 = 32 + 24 * math.cos(a)
        y2 = 32 + 24 * math.sin(a)
        d.line((32, 32, x2, y2), fill=(140, 210, 250, 255), width=4)
        d.ellipse((x2 - 4, y2 - 4, x2 + 4, y2 + 4), fill=(190, 235, 255, 255))
    d.ellipse((26, 26, 38, 38), fill=(190, 235, 255, 255))
    img.save(os.path.join(TEX, "icon_cooling.png"))

    # cargo: crate
    img, d = canvas()
    d.rounded_rectangle((10, 16, 54, 54), radius=6, fill=(160, 108, 40, 255),
                        outline=(96, 62, 20, 255), width=3)
    d.line((10, 34, 54, 34), fill=(96, 62, 20, 255), width=3)
    d.line((32, 16, 32, 54), fill=(96, 62, 20, 255), width=3)
    d.rectangle((26, 10, 38, 20), fill=(210, 160, 70, 255))
    img.save(os.path.join(TEX, "icon_cargo.png"))

    # hull: shield
    img, d = canvas()
    d.polygon([(32, 6), (54, 14), (54, 34), (32, 58), (10, 34), (10, 14)],
              fill=(90, 130, 190, 255))
    d.polygon([(32, 12), (48, 18), (48, 33), (32, 50)], fill=(140, 175, 225, 255))
    img.save(os.path.join(TEX, "icon_hull.png"))

    # mobility: tread wheel + up-ramp arrow
    img, d = canvas()
    d.rounded_rectangle((8, 36, 56, 54), radius=9, fill=(70, 70, 78, 255))
    for x in range(12, 52, 9):
        d.ellipse((x, 40, x + 7, 47), fill=(130, 130, 140, 255))
    d.line((14, 30, 44, 12), fill=(240, 180, 60, 255), width=5)
    d.polygon([(52, 8), (50, 22), (38, 12)], fill=(240, 180, 60, 255))
    img.save(os.path.join(TEX, "icon_mobility.png"))

    # rockets: escape rocket climbing to the upper right, matching the HUD pad
    img, d = canvas()
    d.polygon([(46, 10), (52, 30), (34, 40), (24, 30)], fill=(214, 220, 232, 255))
    d.polygon([(46, 10), (52, 30), (42, 33)], fill=(160, 168, 184, 255))
    d.ellipse((36, 20, 44, 28), fill=(120, 190, 240, 255))          # porthole
    d.polygon([(24, 30), (34, 40), (18, 42)], fill=(222, 92, 60, 255))  # fin
    d.polygon([(34, 40), (24, 54), (16, 48), (24, 44)],
              fill=(250, 176, 64, 255))                             # exhaust flame
    d.polygon([(30, 44), (22, 52), (20, 46)], fill=(255, 232, 150, 255))
    img.save(os.path.join(TEX, "icon_rockets.png"))


def build_half_atlas():
    """Half-resolution (32 px/tile) copy of the tile atlas used by the
    pixel-carved terrain renderer."""
    src = Image.open(os.path.join(TEX, "tiles.png"))
    small = src.resize((src.width // 2, src.height // 2), Image.LANCZOS)
    small.save(os.path.join(TEX, "tiles_32.png"))


def build_factory():
    """The surface shop: an ore refinery, not a cottage.

    The building is the game's thesis in one picture -- raw ore goes up the
    conveyor, the smelter glows, refined metal and money come out. It reads as
    industry so the shop feels like the place your haul is actually processed.
    """
    W, H = 288, 176
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    STEEL = (108, 116, 132)
    STEEL_D = (68, 74, 88)
    STEEL_L = (152, 160, 178)
    RUST = (176, 92, 44)
    HOT = (255, 156, 46)

    ground = H - 8

    # ---- back smokestacks ----
    for sx, sw, sh in ((30, 22, 104), (60, 17, 78)):
        d.rectangle((sx, ground - sh, sx + sw, ground), fill=STEEL_D)
        d.rectangle((sx, ground - sh, sx + sw // 2, ground), fill=STEEL)
        d.rectangle((sx - 3, ground - sh - 6, sx + sw + 3, ground - sh),
                    fill=STEEL_L)
        for band in range(1, 4):
            by = ground - sh + band * (sh // 4)
            d.rectangle((sx, by, sx + sw, by + 3), fill=RUST)

    # ---- storage silos ----
    for cx in (214, 252):
        d.rectangle((cx - 17, ground - 92, cx + 17, ground), fill=STEEL_D)
        d.rectangle((cx - 17, ground - 92, cx + 2, ground), fill=STEEL)
        d.ellipse((cx - 17, ground - 104, cx + 17, ground - 80), fill=STEEL_L)
        d.rectangle((cx - 17, ground - 46, cx + 17, ground - 40), fill=RUST)

    # ---- main shed ----
    d.rectangle((84, ground - 78, 200, ground), fill=(84, 90, 106, 255))
    d.rectangle((84, ground - 78, 142, ground), fill=(100, 107, 124, 255))
    # sawtooth factory roof
    for i in range(4):
        x0 = 84 + i * 29
        d.polygon([(x0, ground - 78), (x0 + 15, ground - 96),
                   (x0 + 29, ground - 78)], fill=STEEL_L)
        d.polygon([(x0 + 15, ground - 96), (x0 + 29, ground - 96),
                   (x0 + 29, ground - 78)], fill=(70, 140, 180, 255))

    # lit windows
    for wx in range(94, 190, 24):
        d.rectangle((wx, ground - 62, wx + 15, ground - 44),
                    fill=(255, 214, 128, 255))
        d.rectangle((wx, ground - 62, wx + 15, ground - 54),
                    fill=(255, 236, 186, 255))
        d.line((wx + 7, ground - 62, wx + 7, ground - 44),
               fill=(120, 92, 40, 255))

    # ---- smelter door, glowing ----
    d.rectangle((126, ground - 34, 160, ground), fill=(38, 26, 22, 255))
    for i, c in enumerate(((90, 30, 14), (170, 62, 20), (240, 120, 30), HOT)):
        inset = i * 3
        d.rectangle((128 + inset, ground - 30 + inset, 158 - inset, ground),
                    fill=(*c, 255))

    # ---- conveyor feeding the smelter ----
    d.polygon([(8, ground - 6), (86, ground - 46), (86, ground - 36),
               (8, ground + 4)], fill=STEEL_D)
    r = random.Random(99)
    for i in range(9):
        t = i / 8.0
        bx = 14 + t * 66
        by = ground - 4 - t * 38
        s = r.randrange(3, 6)
        d.ellipse((bx - s, by - s, bx + s, by + s),
                  fill=(150, 128, 96, 255))
    for i in range(6):
        px = 16 + i * 13
        py = ground + 2 - (i / 5.0) * 38
        d.line((px, py, px, py + 8), fill=STEEL_D, width=2)

    # ---- pipework ----
    d.rectangle((196, ground - 66, 232, ground - 58), fill=STEEL)
    d.rectangle((196, ground - 66, 232, ground - 63), fill=STEEL_L)
    d.rectangle((228, ground - 66, 236, ground - 20), fill=STEEL)

    # ---- sign ----
    d.rectangle((96, ground - 122, 194, ground - 100), fill=(28, 26, 34, 255))
    d.rectangle((96, ground - 122, 194, ground - 118), fill=RUST)
    d.rectangle((99, ground - 119, 191, ground - 103), fill=(46, 42, 54, 255))
    # "ORE" in blocks, readable at any font
    for i, bx in enumerate((110, 134, 158)):
        d.rectangle((bx, ground - 116, bx + 18, ground - 106),
                    fill=(255, 196, 92, 255))
        d.rectangle((bx + 4, ground - 113, bx + 14, ground - 109),
                    fill=(46, 42, 54, 255))

    # ---- ground shadow ----
    d.rectangle((0, ground, W, ground + 6), fill=(0, 0, 0, 60))

    img.save(os.path.join(TEX, "shop.png"))


def build_particles():
    """Particle effects for drilling, impacts, ore collection."""
    # soft white particle dot (dust/debris)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r in range(8, 0, -1):
        a = int(255 * (1 - r / 8.0) ** 1.5)
        d.ellipse((8 - r, 8 - r, 8 + r, 8 + r), fill=(255, 255, 255, a))
    img.save(os.path.join(TEX, "particle.png"))

    # ore sparkle (golden glint)
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(6, 0), (12, 6), (6, 12), (0, 6)], fill=(255, 220, 100, 255))
    d.polygon([(6, 3), (9, 6), (6, 9), (3, 6)], fill=(255, 250, 150, 255))
    img.save(os.path.join(TEX, "sparkle_ore.png"))

    # ether shimmer (cyan glow)
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r in range(6, 0, -1):
        a = int(220 * (1 - r / 6.0) ** 1.2)
        d.ellipse((6 - r, 6 - r, 6 + r, 6 + r), fill=(100, 200, 255, a))
    d.ellipse((4, 4, 8, 8), fill=(200, 255, 255, 255))
    img.save(os.path.join(TEX, "sparkle_ether.png"))

    # impact flash (white burst)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(4):
        a = i * 90 / 3.14159
        x2 = 8 + 8 * math.cos(a)
        y2 = 8 + 8 * math.sin(a)
        d.line((8, 8, x2, y2), fill=(255, 255, 200, 200), width=2)
    d.ellipse((4, 4, 12, 12), fill=(255, 255, 255, 200))
    img.save(os.path.join(TEX, "impact.png"))

    # heat shimmer (orange wavy)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(16):
        y = 2 + int(12 * math.sin(i * 0.5))
        a = 100 + 100 * math.sin(i * 0.3)
        d.point((i, 8 + y), fill=(255, 150, 50, int(a)))
    img.save(os.path.join(TEX, "heat_shimmer.png"))


def build_misc():
    # Build particle effects first
    build_particles()

    build_factory()

    # app icon
    img = Image.new("RGBA", (512, 512), (26, 22, 32, 255))
    d = ImageDraw.Draw(img)
    for i in range(5):
        y = 200 + i * 62
        c = LAYER_SOFT[i]
        d.rectangle((0, y, 512, y + 62), fill=(*c, 255))
    d.polygon([(160, 120), (352, 120), (256, 420)], fill=(210, 214, 224, 255))
    d.polygon([(200, 120), (256, 120), (256, 340)], fill=(150, 155, 168, 255))
    d.rounded_rectangle((140, 40, 372, 140), radius=30, fill=(230, 126, 34, 255),
                        outline=(120, 60, 12, 255), width=8)
    d.ellipse((196, 60, 262, 118), fill=(160, 220, 250, 255))
    d.polygon([(410, 300), (452, 342), (410, 384), (368, 342)], fill=(232, 57, 90, 255))
    img.save(os.path.join(ROOT, "icon.png"))


# ------------------------------------------------------------------ audio

SR = 22050


def write_wav(name, samples):
    path = os.path.join(AUD, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767))))
                          for s in samples)
        w.writeframes(frames)


def env(i, n, a=0.01, r=0.3):
    t = i / n
    attack = min(1.0, t / max(a, 1e-6))
    release = min(1.0, (1.0 - t) / max(r, 1e-6))
    return min(attack, release)


def sine(freq, dur, vol=0.5, a=0.01, r=0.3):
    n = int(SR * dur)
    return [math.sin(2 * math.pi * freq * i / SR) * vol * env(i, n, a, r) for i in range(n)]


def noise(dur, vol=0.5, lp=0.2, a=0.01, r=0.5):
    n = int(SR * dur)
    out, prev = [], 0.0
    for i in range(n):
        prev += lp * (rng.uniform(-1, 1) - prev)
        out.append(prev * vol * env(i, n, a, r))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    peak = max(1.0, max(abs(s) for s in out))
    return [s / peak * 0.9 for s in out]


def concat(*tracks):
    out = []
    for t in tracks:
        out.extend(t)
    return out


def build_audio():
    write_wav("click.wav", sine(1100, 0.05, 0.5, 0.002, 0.6))
    write_wav("pickup.wav", concat(sine(660, 0.07, 0.45, 0.004, 0.3),
                                   sine(990, 0.10, 0.45, 0.004, 0.5)))
    write_wav("sell.wav", concat(sine(523, 0.08, 0.4, 0.005, 0.3),
                                 sine(659, 0.08, 0.4, 0.005, 0.3),
                                 sine(784, 0.16, 0.45, 0.005, 0.6)))
    write_wav("upgrade.wav", concat(sine(392, 0.09, 0.4, 0.005, 0.3),
                                    sine(523, 0.09, 0.4, 0.005, 0.3),
                                    sine(659, 0.09, 0.4, 0.005, 0.3),
                                    sine(784, 0.22, 0.5, 0.005, 0.7)))
    # loopable drill rumble
    n = int(SR * 0.8)
    drill, prev = [], 0.0
    for i in range(n):
        prev += 0.12 * (rng.uniform(-1, 1) - prev)
        rumble = 0.35 * math.sin(2 * math.pi * 55 * i / SR)
        grind = 0.30 * math.sin(2 * math.pi * 170 * i / SR + 3 * prev)
        drill.append((prev * 0.5 + rumble + grind) * 0.55)
    write_wav("drill_loop.wav", drill)

    # loopable jet hiss
    n = int(SR * 0.6)
    jet, prev = [], 0.0
    for i in range(n):
        prev += 0.45 * (rng.uniform(-1, 1) - prev)
        jet.append(prev * 0.35)
    write_wav("jet_loop.wav", jet)

    write_wav("explosion.wav", mix(noise(0.9, 0.9, 0.10, 0.005, 0.8),
                                   sine(70, 0.9, 0.7, 0.005, 0.9)))
    write_wav("hurt.wav", [math.sin(2 * math.pi * (300 - 180 * i / (SR * 0.18)) * i / SR)
                           * 0.5 * env(i, int(SR * 0.18), 0.01, 0.4)
                           for i in range(int(SR * 0.18))])
    write_wav("warning.wav", concat(sine(880, 0.12, 0.4, 0.01, 0.3),
                                    [0.0] * int(SR * 0.08),
                                    sine(880, 0.12, 0.4, 0.01, 0.3)))
    write_wav("splash.wav", noise(0.35, 0.5, 0.5, 0.005, 0.7))
    write_wav("bust.wav", concat(sine(440, 0.15, 0.5, 0.01, 0.3),
                                 sine(415, 0.15, 0.5, 0.01, 0.3),
                                 sine(392, 0.35, 0.5, 0.01, 0.7)))

    # new sfx: impact/collision sounds
    write_wav("impact_rock.wav", noise(0.2, 0.6, 0.3, 0.01, 0.4))
    write_wav("impact_ore.wav", concat(sine(880, 0.08, 0.5, 0.005, 0.3),
                                       noise(0.15, 0.3, 0.3, 0.01, 0.3)))
    write_wav("enemy_alert.wav", concat(sine(660, 0.1, 0.4, 0.01, 0.2),
                                        [0.0] * int(SR * 0.05),
                                        sine(880, 0.1, 0.4, 0.01, 0.2)))

    # mini-boss laser drill sound
    n = int(SR * 0.6)
    laser = []
    for i in range(n):
        freq = 200 + 400 * (i / n)
        laser.append(math.sin(2 * math.pi * freq * i / SR) * 0.4 * env(i, n, 0.05, 0.3))
    write_wav("laser_drill.wav", laser)

    # layer transition rumble (deep and resonant)
    write_wav("layer_transition.wav", mix(sine(60, 0.4, 0.5, 0.05, 0.3),
                                          sine(120, 0.4, 0.4, 0.05, 0.3),
                                          noise(0.4, 0.3, 0.15, 0.05, 0.3)))

    # ambient music loop: Am F C G pad, 9.6 s
    chords = [(220.0, 261.63, 329.63), (174.61, 220.0, 261.63),
              (261.63, 329.63, 392.0), (196.0, 246.94, 293.66)]
    seg = int(SR * 2.4)
    music = []
    for ci, chord in enumerate(chords):
        for i in range(seg):
            t = (ci * seg + i) / SR
            fade = env(i, seg, 0.25, 0.25)
            s = 0.0
            for f in chord:
                s += math.sin(2 * math.pi * f * 0.5 * (ci * seg + i) / SR)
            lfo = 0.85 + 0.15 * math.sin(2 * math.pi * 0.15 * t)
            music.append(s / 3.0 * 0.30 * fade * lfo)
    write_wav("music_loop.wav", music)

    # layer-specific ambient layers (deep rumble for deeper levels)
    for layer_idx in range(5):
        base_freq = 40 + layer_idx * 30  # deeper as you go down
        depth_mod = 0.8 + layer_idx * 0.15
        n = int(SR * 2.0)
        ambient = []
        for i in range(n):
            s = 0.0
            for harmonic in [1, 2, 3]:
                s += math.sin(2 * math.pi * base_freq * harmonic * i / SR) * (1.0 / (harmonic * 2))
            s *= 0.25 * depth_mod * env(i, n, 0.3, 0.3)
            ambient.append(s)
        write_wav(f"ambient_layer{layer_idx + 1}.wav", ambient)


if __name__ == "__main__":
    build_tile_atlas()
    build_half_atlas()
    build_player()
    build_drill_skins()
    build_crawly()
    build_enemy_variants()
    build_new_enemies()
    build_zombie()
    build_govt()
    build_upgrade_icons()
    build_misc()
    build_audio()
    print("Assets generated:")
    for folder in (TEX, AUD):
        for f in sorted(os.listdir(folder)):
            print("  ", os.path.join(os.path.relpath(folder, ROOT), f))
    print("   icon.png")
