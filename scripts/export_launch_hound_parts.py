#!/usr/bin/env python3
"""Cut the MilehoundHound silhouette into a gallop rig for the cold-launch intro.

Writes the part imagesets on the original canvas, so every part lines up with the logo
when drawn in the same rect: front and rear body (split at the spine), tail, and each leg
as an upper and a lower segment (split at the knee, hock, or elbow).

With `--gait`, also fits the run cycle of a bone-rigged Lottie into Fourier curves and
prints `LaunchIntroHoundRig.standard`. The curves in the app come from "Blackhound" by
Julio Gonzalez on LottieFiles (Lottie Simple License); only its motion is used, mirrored
to face right and phase-aligned so that phase 0 is the logo pose.

    python3 scripts/export_launch_hound_parts.py [--preview] [--gait blackhound.json]
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow required: pip install pillow", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Milehound" / "Assets.xcassets"
SOURCE = ASSETS / "MilehoundHound.imageset" / "MilehoundHound.png"
PREVIEW = Path("/tmp/hound_rig_preview.png")
PREFIX = "MilehoundHound"

SOLID = 128
EDGE_GROW = 2
CAP_MARGIN = 2
# A knee cap no wider than the leg turns inside its own circle, so a bending joint stays round.
KNEE_MARGIN = 0
SPINE_X = 350

# name, cut row (None for a limb that does not touch the body), seed inside the limb,
# bend (knee / hock / elbow, None for a single piece). Each cut sits where the limb first
# separates from the body, so no static stub is left under a swinging leg.
LIMBS = [
    ("Tail", 190, (30, 230), None),
    ("HindReach", 200, (120, 385), (125, 280)),
    ("HindTuck", 168, (345, 360), (262, 278)),
    ("ForeReach", 204, (395, 385), (400, 350)),
    ("ForeFold", None, (510, 250), (540, 285)),
]
HIND = ("HindReach", "HindTuck")
FORE = ("ForeReach", "ForeFold")
NEAR = ("HindReach", "ForeReach")

CONTENTS = {
    "images": [{"filename": "", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"template-rendering-intent": "template"},
}

NEIGHBORS = ((1, 0), (-1, 0), (0, 1), (0, -1))


# MARK: - Cutting


def flood(alpha, size, seed, top):
    width, height = size
    sx, sy = seed
    if alpha[sx, sy] <= SOLID or sy < top:
        raise SystemExit(f"seed {seed} is not inside the silhouette below row {top}")
    seen = {seed}
    queue = deque([seed])
    while queue:
        x, y = queue.popleft()
        for dx, dy in NEIGHBORS:
            nx, ny = x + dx, y + dy
            if top <= ny < height and 0 <= nx < width and (nx, ny) not in seen and alpha[nx, ny] > SOLID:
                seen.add((nx, ny))
                queue.append((nx, ny))
    return seen


def grow(points, alpha, size, top):
    """Soft edge pixels around a solid region, never above its cut, each owned by its nearest solid pixel."""
    width, height = size
    owner = {}
    for x, y in points:
        for dx in range(-EDGE_GROW, EDGE_GROW + 1):
            for dy in range(-EDGE_GROW, EDGE_GROW + 1):
                nx, ny = x + dx, y + dy
                if top <= ny < height and 0 <= nx < width and alpha[nx, ny] > 0:
                    d = dx * dx + dy * dy
                    if (nx, ny) not in owner or d < owner[(nx, ny)][0]:
                        owner[(nx, ny)] = (d, (x, y))
    return {p: o for p, (_, o) in owner.items()}


def geodesic(points, starts):
    dist = {p: 0 for p in starts}
    queue = deque(starts)
    while queue:
        x, y = queue.popleft()
        for dx, dy in NEIGHBORS:
            n = (x + dx, y + dy)
            if n in points and n not in dist:
                dist[n] = dist[(x, y)] + 1
                queue.append(n)
    return dist


def disc(points, center, radius):
    cx, cy = center
    return {(x, y) for x, y in points if (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2}


def centroid(points):
    return (sum(x for x, _ in points) / len(points), sum(y for _, y in points) / len(points))


def cut_limb(alpha, size, silhouette, cut, seed, bend):
    top = cut if cut is not None else 0
    solid = flood(alpha, size, seed, top)
    owner = grow(solid, alpha, size, top)
    if cut is not None:
        row = [x for x, y in solid if y == cut]
        if not row:
            raise SystemExit(f"limb does not reach its cut row {cut}")
        hip = (sum(row) / len(row), float(cut))
        hip_half = (max(row) - min(row) + 1) / 2
        starts = [(x, y) for x, y in solid if y == cut]
    else:
        first = min(y for _, y in solid)
        row = [x for x, y in solid if y == first]
        hip = (sum(row) / len(row), float(first))
        hip_half = 0
        starts = [(x, y) for x, y in solid if y == first]

    limb = set(owner)
    hip_cap = set()
    if cut is not None:
        hip_cap = {p for p in disc(silhouette, hip, hip_half + CAP_MARGIN) if p[1] < cut}

    if bend is None:
        return {"joint": hip, "upper": limb | hip_cap, "taken": limb}

    dist = geodesic(solid, starts)
    nearest = min(dist, key=lambda p: (p[0] - bend[0]) ** 2 + (p[1] - bend[1]) ** 2)
    threshold = dist[nearest]
    lower_solid = {p for p, d in dist.items() if d > threshold}
    band = [p for p, d in dist.items() if abs(d - threshold) <= 1]
    knee = centroid(band)
    knee_half = max(math.dist(knee, p) for p in band)
    upper = {p for p, o in owner.items() if o not in lower_solid}
    lower = {p for p, o in owner.items() if o in lower_solid}
    radius = knee_half + KNEE_MARGIN
    toe = max(lower_solid, key=lambda p: math.dist(knee, p))
    return {
        "joint": hip,
        "knee": knee,
        "toe": toe,
        "upper": upper | hip_cap | disc(lower, knee, radius),
        "lower": lower | disc(upper, knee, radius),
        "taken": limb,
    }


def split_body(body):
    column = [y for x, y in body if x == SPINE_X]
    top, bottom = min(column), max(column)
    spine = (float(SPINE_X), (top + bottom) / 2)
    radius = (bottom - top) / 2 + CAP_MARGIN
    rear = {p for p in body if p[0] < SPINE_X}
    front = body - rear
    rear |= disc(front, spine, radius)
    return spine, front, rear


def write_part(image, mask, name):
    width, height = image.size
    src = image.load()
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dst = out.load()
    for x, y in mask:
        dst[x, y] = src[x, y]
    asset = PREFIX + name
    folder = ASSETS / f"{asset}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"{asset}.png"
    out.save(folder / filename, "PNG", optimize=True)
    contents = json.loads(json.dumps(CONTENTS))
    contents["images"][0]["filename"] = filename
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2, separators=(",", " : ")) + "\n")


def angle(a, b):
    return math.atan2(b[1] - a[1], b[0] - a[0])


# MARK: - Gait from a bone-rigged Lottie


class Lottie:
    """Forward kinematics for the Blackhound rig (layer indices are that file's)."""

    RIBS, BELLY = 11, 19
    # hip/shoulder bone, bone that pivots at the hock/wrist, bone whose far tip is the toe
    CHAINS = {
        "hindNear": (18, 16, 15),
        "hindFar": (23, 21, 20),
        "foreNear": (10, 8, 8),
        "foreFar": (14, 12, 12),
    }

    def __init__(self, path):
        data = json.load(open(path))
        self.layers = {l["ind"]: l for l in data["layers"]}
        ribs = self.layers[self.RIBS]["ks"]["r"]["k"]
        self.start, self.end = ribs[1]["t"], ribs[-1]["t"]

    @staticmethod
    def ease(o, i, x):
        ox, oy, ix, iy = (v[0] if isinstance(v, list) else v for v in (o["x"], o["y"], i["x"], i["y"]))
        lo, hi = 0.0, 1.0
        for _ in range(40):
            u = (lo + hi) / 2
            if 3 * (1 - u) ** 2 * u * ox + 3 * (1 - u) * u ** 2 * ix + u ** 3 < x:
                lo = u
            else:
                hi = u
        u = (lo + hi) / 2
        return 3 * (1 - u) ** 2 * u * oy + 3 * (1 - u) * u ** 2 * iy + u ** 3

    def value(self, prop, t):
        if prop.get("a") != 1:
            k = prop["k"]
            return k if isinstance(k, list) else [k]
        frames = prop["k"]
        if t <= frames[0]["t"]:
            return frames[0]["s"]
        for a, b in zip(frames, frames[1:]):
            if a["t"] <= t < b["t"]:
                if "e" not in a or a.get("h"):
                    return a["s"]
                x = (t - a["t"]) / (b["t"] - a["t"])
                if a.get("o") and a.get("i"):
                    x = self.ease(a["o"], a["i"], x)
                return [s + (e - s) * x for s, e in zip(a["s"], a["e"])]
        last = frames[-2]
        return last.get("e", last["s"])

    def local(self, ks, t):
        p, a, s = self.value(ks["p"], t), self.value(ks["a"], t), self.value(ks["s"], t)
        r = math.radians(self.value(ks["r"], t)[0]) if "r" in ks else 0.0
        c, n = math.cos(r), math.sin(r)
        m = [[c * s[0] / 100, -n * s[1] / 100, 0.0], [n * s[0] / 100, c * s[1] / 100, 0.0]]
        m[0][2] = p[0] - (m[0][0] * a[0] + m[0][1] * a[1])
        m[1][2] = p[1] - (m[1][0] * a[0] + m[1][1] * a[1])
        return m

    @staticmethod
    def mul(a, b):
        return [
            [a[r][0] * b[0][0] + a[r][1] * b[1][0], a[r][0] * b[0][1] + a[r][1] * b[1][1], a[r][0] * b[0][2] + a[r][1] * b[1][2] + a[r][2]]
            for r in range(2)
        ]

    @staticmethod
    def apply(m, q):
        return (m[0][0] * q[0] + m[0][1] * q[1] + m[0][2], m[1][0] * q[0] + m[1][1] * q[1] + m[1][2])

    def world(self, ind, t):
        layer = self.layers[ind]
        m = self.local(layer["ks"], t)
        parent = layer.get("parent")
        return self.mul(self.world(parent, t), m) if parent else m

    def joint(self, ind, t):
        layer = self.layers[ind]
        p = self.value(layer["ks"]["p"], t)
        parent = layer.get("parent")
        return self.apply(self.world(parent, t), p) if parent else (p[0], p[1])

    def tip(self, ind, t, base):
        m = self.world(ind, t)
        best = None
        for group in self.layers[ind].get("shapes", []):
            tr = next((i for i in group.get("it", []) if i["ty"] == "tr"), None)
            gm = self.local(tr, t) if tr else [[1, 0, 0], [0, 1, 0]]
            for item in group.get("it", []):
                if item["ty"] != "sh":
                    continue
                for v in item["ks"]["k"]["v"]:
                    w = self.apply(m, self.apply(gm, v))
                    d = math.dist(w, base)
                    if best is None or d > best[0]:
                        best = (d, w)
        return best[1]

    def pose(self, phase):
        """World angles mirrored to face right (y down, positive is clockwise)."""
        t = self.start + (self.end - self.start) * phase
        ribs = math.radians(self.value(self.layers[self.RIBS]["ks"]["r"], t)[0])
        belly = math.radians(self.value(self.layers[self.BELLY]["ks"]["r"], t)[0])
        out = {"front": -ribs, "rear": -ribs - belly}
        for name, (hip, mid, end) in self.CHAINS.items():
            a, b = self.joint(hip, t), self.joint(mid, t)
            c = self.tip(end, t, b)
            out[name] = (math.pi - angle(a, b), math.pi - angle(b, c))
        return out


def unwrap(values):
    out = [values[0]]
    for v in values[1:]:
        while v - out[-1] > math.pi:
            v -= 2 * math.pi
        while v - out[-1] < -math.pi:
            v += 2 * math.pi
        out.append(v)
    return out


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def fourier(samples, harmonics):
    n = len(samples)
    cosines, sines = [sum(samples) / n], [0.0]
    for k in range(1, harmonics + 1):
        cosines.append(2 / n * sum(v * math.cos(2 * math.pi * k * i / n) for i, v in enumerate(samples)))
        sines.append(2 / n * sum(v * math.sin(2 * math.pi * k * i / n) for i, v in enumerate(samples)))
    return cosines, sines


SAMPLES = 96
HARMONICS = 4
LEG_GAIN = 0.85
PITCH_GAIN = 0.35
SPINE_GAIN = 0.45
TAIL_SWING = 0.12
BOB = 0.02


def fit_gait(path, art):
    lottie = Lottie(path)
    poses = [lottie.pose(i / SAMPLES) for i in range(SAMPLES)]
    front = unwrap([p["front"] for p in poses])
    rear = unwrap([p["rear"] for p in poses])
    series = {
        "pitch": front,
        "spine": [r - f for r, f in zip(rear, front)],
    }
    # Legs are measured against their body half as it sits on average, which is taken as level like the logo.
    front_level = sum(front) / SAMPLES
    rear_level = sum(rear) / SAMPLES
    for chain in Lottie.CHAINS:
        body = front if chain.startswith("fore") else rear
        level = front_level if chain.startswith("fore") else rear_level
        upper = unwrap([p[chain][0] for p in poses])
        lower = unwrap([p[chain][1] for p in poses])
        series[chain + ".upper"] = [u - (b - level) for u, b in zip(upper, body)]
        series[chain + ".lower"] = [l - u for l, u in zip(lower, upper)]

    # Phase and near/far pairing whose pose is closest to the logo.
    best = None
    pairings = [
        {"HindReach": "hindNear", "HindTuck": "hindFar"},
        {"HindReach": "hindFar", "HindTuck": "hindNear"},
    ]
    fore_pairings = [
        {"ForeReach": "foreNear", "ForeFold": "foreFar"},
        {"ForeReach": "foreFar", "ForeFold": "foreNear"},
    ]
    for hind in pairings:
        for fore in fore_pairings:
            pairing = {**hind, **fore}
            for i in range(SAMPLES):
                error = 0.0
                for leg, chain in pairing.items():
                    error += wrap(series[chain + ".upper"][i] - art[leg][0]) ** 2
                    error += wrap(series[chain + ".lower"][i] - art[leg][1]) ** 2
                if best is None or error < best[0]:
                    best = (error, i, pairing)
    _, start, pairing = best
    print(f"logo pose ~ reference phase {start / SAMPLES:.3f}, pairing {pairing}", file=sys.stderr)

    def curve(values, gain, rest):
        """Offset from the logo pose toward `gain` of the reference, which starts at `rest`."""
        shifted = values[start:] + values[:start]
        return fourier([gain * wrap(v - rest) for v in shifted], HARMONICS)

    curves = {
        "pitch": curve(series["pitch"], PITCH_GAIN, series["pitch"][start]),
        "spine": curve(series["spine"], SPINE_GAIN, series["spine"][start]),
    }
    for leg, chain in pairing.items():
        curves[leg + "Upper"] = curve(series[chain + ".upper"], LEG_GAIN, art[leg][0])
        curves[leg + "Lower"] = curve(series[chain + ".lower"], LEG_GAIN, art[leg][1])
    # The reference rig does not move the body up or down or the tail; lift on both flights, flick the tail.
    gathered = start / SAMPLES
    curves["bob"] = fourier([-BOB * math.cos(4 * math.pi * (i / SAMPLES + gathered)) for i in range(SAMPLES)], HARMONICS)
    curves["Tail"] = fourier([TAIL_SWING * math.sin(2 * math.pi * (i / SAMPLES + gathered + 0.25)) for i in range(SAMPLES)], HARMONICS)
    return curves


# MARK: - Swift


def swift_curve(c):
    if c is None:
        return ".still"
    cosines, sines = c
    fmt = lambda xs: ", ".join(f"{x:.4f}" for x in xs)
    return f"Curve(bias: {cosines[0]:.4f}, cosines: [{fmt(cosines[1:])}], sines: [{fmt(sines[1:])}])"


def swift_point(p):
    return f"CGPoint(x: {p[0]:.1f}, y: {p[1]:.1f})"


def swift_rig(size, joints, curves):
    def leg(name, indent):
        pad = " " * indent
        lower = (
            f"{pad}        Bone(asset: \"{PREFIX}{name}Lower\", joint: {swift_point(joints[name + 'Lower'])}, "
            f"swing: {swift_curve(curves.get(name + 'Lower'))})"
        )
        return (
            f"{pad}Bone(\n"
            f"{pad}    asset: \"{PREFIX}{name}Upper\",\n"
            f"{pad}    joint: {swift_point(joints[name + 'Upper'])},\n"
            f"{pad}    swing: {swift_curve(curves.get(name + 'Upper'))},\n"
            f"{pad}    front: [\n{lower}\n{pad}    ]\n"
            f"{pad})"
        )

    far_hind = [n for n in HIND if n not in NEAR]
    near_hind = [n for n in HIND if n in NEAR]
    far_fore = [n for n in FORE if n not in NEAR]
    near_fore = [n for n in FORE if n in NEAR]
    tail = f"Bone(asset: \"{PREFIX}Tail\", joint: {swift_point(joints['Tail'])}, swing: {swift_curve(curves.get('Tail'))})"
    rear_behind = ",\n".join([" " * 24 + tail] + [leg(n, 24) for n in far_hind])
    rear_front = ",\n".join(leg(n, 24) for n in near_hind)
    torso_behind_legs = ",\n".join(leg(n, 16) for n in far_fore)
    torso_front = ",\n".join(leg(n, 16) for n in near_fore)
    return f"""    static let standard = LaunchIntroHoundRig(
        canvas: CGSize(width: {size[0]}, height: {size[1]}),
        torso: Bone(
            asset: "{PREFIX}Front",
            joint: {swift_point(joints['Front'])},
            swing: {swift_curve(curves.get('pitch'))},
            behind: [
{torso_behind_legs},
                Bone(
                    asset: "{PREFIX}Rear",
                    joint: {swift_point(joints['Rear'])},
                    swing: {swift_curve(curves.get('spine'))},
                    behind: [
{rear_behind}
                    ],
                    front: [
{rear_front}
                    ]
                )
            ],
            front: [
{torso_front}
            ]
        ),
        bob: {swift_curve(curves.get('bob'))},
        stride: MilehoundMotion.launchIntroGallopStride
    )"""


# MARK: - Main


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true", help=f"write {PREVIEW}")
    parser.add_argument("--gait", type=Path, help="bone-rigged Lottie JSON to fit the run cycle from")
    args = parser.parse_args()

    image = Image.open(SOURCE).convert("RGBA")
    size = image.size
    alpha = image.split()[3].load()
    silhouette = {(x, y) for x in range(size[0]) for y in range(size[1]) if alpha[x, y] > 0}

    taken = set()
    parts = {}
    joints = {}
    art = {}
    for name, cut, seed, bend in LIMBS:
        limb = cut_limb(alpha, size, silhouette, cut, seed, bend)
        taken |= limb["taken"]
        if bend is None:
            parts[name] = limb["upper"]
            joints[name] = limb["joint"]
            continue
        parts[name + "Upper"] = limb["upper"]
        parts[name + "Lower"] = limb["lower"]
        joints[name + "Upper"] = limb["joint"]
        joints[name + "Lower"] = limb["knee"]
        upper = angle(limb["joint"], limb["knee"])
        art[name] = (upper, angle(limb["knee"], limb["toe"]) - upper)

    body = silhouette - taken
    spine, front, rear = split_body(body)
    parts["Front"] = front
    parts["Rear"] = rear
    joints["Front"] = (370.0, 180.0)
    joints["Rear"] = spine

    union = set()
    for mask in parts.values():
        union |= mask
    if union != silhouette:
        raise SystemExit(f"rig does not rebuild the silhouette: {len(silhouette ^ union)} pixels differ")

    for name, mask in parts.items():
        write_part(image, mask, name)

    print(f"canvas {size[0]}x{size[1]}", file=sys.stderr)
    for name, joint in joints.items():
        print(f"  {name:16} joint ({joint[0]:.1f}, {joint[1]:.1f})", file=sys.stderr)
    for name, (u, l) in art.items():
        print(f"  {name:16} upper {math.degrees(u):6.1f}  lower {math.degrees(l):6.1f}", file=sys.stderr)

    if args.gait:
        print(swift_rig(size, joints, fit_gait(args.gait, art)))

    if args.preview:
        colors = [(255, 120, 80), (80, 200, 120), (40, 140, 80), (80, 160, 255), (40, 90, 200),
                  (230, 200, 60), (170, 140, 20), (200, 100, 230), (130, 50, 170), (235, 235, 235), (190, 190, 190)]
        preview = Image.new("RGBA", size, (30, 30, 30, 255))
        pv = preview.load()
        for (name, mask), color in zip(sorted(parts.items(), key=lambda kv: kv[0] not in ("Front", "Rear")), colors):
            for x, y in mask:
                pv[x, y] = color + (255,)
        for jx, jy in joints.values():
            for dx in range(-4, 5):
                for dy in range(-4, 5):
                    if dx * dx + dy * dy <= 16:
                        pv[int(jx) + dx, int(jy) + dy] = (255, 0, 0, 255)
        preview.resize((size[0] * 2, size[1] * 2), Image.NEAREST).save(PREVIEW)
        print(f"preview {PREVIEW}", file=sys.stderr)


if __name__ == "__main__":
    main()
