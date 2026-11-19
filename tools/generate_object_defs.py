"""One-off importer: reads the object tables from the original TBE C++ sources
and writes one ObjectDef .tres per object type into objects/defs/.

Usage:  python tools/generate_object_defs.py <path-to-tbe-original>

After this initial import, the .tres files are the source of truth: edit them
in the Godot Inspector. Re-running this script overwrites generated files but
never touches defs whose name is not produced by it.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "objects", "defs")


def split_args(s):
    args, depth, cur, in_str = [], 0, "", False
    i = 0
    while i < len(s):
        c = s[i]
        if in_str:
            cur += c
            if c == "\\":
                cur += s[i + 1]
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur += c
        elif c == "(":
            depth += 1
            cur += c
        elif c == ")":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        args.append(cur.strip())
    return args


def strings_in(arg):
    lits = re.findall(r'"((?:[^"\\]|\\.)*)"', arg)
    return lits


def text_of(arg):
    """QT_TRANSLATE_NOOP("ctx", "text") -> text ; "a" "b" -> ab"""
    lits = strings_in(arg)
    if arg.startswith("QT_TRANSLATE"):
        lits = lits[1:]
    return "".join(lits).replace("\\n", "\n").replace('\\"', '"')


def parse_props(s):
    props = {}
    for part in s.split("/"):
        if ":" in part:
            k, v = part.split(":", 1)
            props[k.strip()] = v.strip()
    return props


def parse_polys(outline):
    """Returns (polygons, aabb_size). Like the original, the bounding box
    includes stray single points, which some outlines use to set the size."""
    polys, allpts = [], []
    for p in outline.split(";"):
        pts = [(float(x), float(y)) for x, y in re.findall(r"\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)", p)]
        allpts += pts
        if len(pts) >= 3:
            polys.append(pts)
    xs = [x for x, _ in allpts] or [0, 1]
    ys = [y for _, y in allpts] or [0, 1]
    return polys, (max(xs) - min(xs), max(ys) - min(ys))


def fit_polys(polys_and_box, w, h):
    """Scale outline so its bounding box matches the object's size."""
    polys, (bw, bh) = polys_and_box
    sx = w / bw if bw else 1.0
    sy = h / bh if bh else 1.0
    return [[(x * sx, y * sy) for x, y in p] for p in polys]


def factories(src, cls):
    src = re.sub(r"(?m)^\s*//[^\n]*$", "", src)
    pat = re.compile(r"static\s+" + cls + r"\s+\w+\s*\(")
    for m in pat.finditer(src):
        # scan to the matching ')' while respecting string literals
        i, depth, in_str = m.end(), 1, False
        while depth:
            c = src[i]
            if in_str:
                if c == "\\":
                    i += 1
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            i += 1
        body = re.sub(r"//[^\n\"]*\n", "\n", src[m.end():i - 1])
        yield split_args(body)


def num(a):
    return float(a)


CATEGORY = {
    "Floor": "Fixed", "Wall": "Fixed", "LeftFixedWedge": "Fixed", "RightFixedWedge": "Fixed",
    "QuarterArc40": "Fixed", "QuarterArc80": "Fixed", "PegMetal": "Fixed", "PegWood": "Fixed",
    "Skyhook": "Fixed", "Goal": "Fixed", "BedOfNails": "Fixed",
    "DominoRed": "Dominoes", "DominoBlue": "Dominoes", "DominoGreen": "Dominoes",
    "BowlingBall": "Balls", "VolleyBall": "Balls", "TennisBall": "Balls", "SoccerBall": "Balls",
    "PetanqueBoule": "Balls", "CustomBall": "Balls",
    "LeftRamp": "Ramps", "RightRamp": "Ramps", "LeftWedge": "Ramps", "RightWedge": "Ramps",
    "LeftStyrofoamWedge": "Ramps", "RightStyrofoamWedge": "Ramps",
}


def default_category(d):
    if d["type_name"] in CATEGORY:
        return CATEGORY[d["type_name"]]
    return "Fixed" if d.get("mass", 0) == 0 else "Blocks"


def collect(tbe):
    model = os.path.join(tbe, "src", "model")
    defs = []

    src = open(os.path.join(model, "RectObject.cpp"), encoding="utf-8").read()
    for a in factories(src, "AbstractRectObjectFactory"):
        d = dict(type_name=text_of(a[0]), display_name=text_of(a[1]), tooltip=text_of(a[2]),
                 image=text_of(a[3]), width=num(a[4]), height=num(a[5]), mass=num(a[6]),
                 bounciness=num(a[7]), shape=0, extra=parse_props(text_of(a[8])) if len(a) > 8 else {})
        defs.append(d)

    src = open(os.path.join(model, "CircleObjects.cpp"), encoding="utf-8").read()
    for a in factories(src, "CircleObjectFactory"):
        r = num(a[4])
        defs.append(dict(type_name=text_of(a[0]), display_name=text_of(a[1]), tooltip=text_of(a[2]),
                         image=text_of(a[3]), width=2 * r, height=2 * r, mass=num(a[5]),
                         bounciness=num(a[6]), shape=1, extra={}))

    src = open(os.path.join(model, "PolyObject.cpp"), encoding="utf-8").read()
    for a in factories(src, "AbstractPolyObjectFactory"):
        extra = {}
        if len(a) > 9:
            if "ZVALUE" in a[9]:
                extra = {"ZValue": text_of(a[9]).lstrip(":")}
            else:
                extra = parse_props(text_of(a[9]))
        defs.append(dict(type_name=text_of(a[0]), display_name=text_of(a[1]), tooltip=text_of(a[2]),
                         image=text_of(a[3]), polygons=fit_polys(parse_polys(text_of(a[4])), num(a[5]), num(a[6])),
                         width=num(a[5]), height=num(a[6]), mass=num(a[7]), bounciness=num(a[8]),
                         shape=2, extra=extra))

    # Objects with special behaviors: values copied from their C++ constructors.
    defs += [
        dict(type_name="Butterfly", display_name="Butterfly", category="Characters",
             tooltip="A butterfly. It wants to reach a flower.",
             image="ButterflyStill;ButterflyOpen;ButterflyHalfOpen;ButterflyStill", shape=0,
             width=0.15, height=0.228, mass=0.01, bounciness=0.0, behavior="butterfly"),
        dict(type_name="Balloon", display_name="Helium Balloon", category="Characters",
             tooltip="A helium balloon. Lighter than air, it moves up.\nIt will pop when it hits sharp objects or gets squashed.",
             image="Balloon;BalloonPoof;BalloonRest;Empty", shape=2, width=0.27, height=0.36, mass=0.1,
             bounciness=0.7, behavior="balloon",
             polygons=parse_polys("(-0.018,0.18)=(-0.07,0.16)=(-0.12,0.1)=(-0.13,0.017)=(-0.1,-0.08)"
                                  "=(-0.03,-0.16)=(0.006,-0.17)=(0.039,-0.16)=(0.10,-0.08)"
                                  "=(0.13,0.015)=(0.11,0.11)=(0.07,0.16)=(0.01,0.18)")),
        dict(type_name="Cactus", display_name="Cactus", category="Dangerous",
             tooltip="Cactus (Cactacea Bulbuous Stingus):\nA cactus has sharp spines.",
             image="Cactus", shape=2, width=0.25, height=0.4, mass=1.0, bounciness=0.3, behavior="sharp",
             extra={"SharpAbove": "-0.036"},
             polygons=parse_polys("(-0.105,-0.038)=(-0.05,-0.2)=(0.05,-0.2)=(0.105,-0.038);"
                                  "(0.045,-0.036)=(0.085,0.012)=(0.092,0.089)=(0.046,0.156)=(0.00,0.171)"
                                  "=(-0.046,0.156)=(-0.092,0.089)=(-0.085,0.012)=(-0.045,-0.036);(-0.125,-0.2);(0.125,0.2)")),
        dict(type_name="BedOfNails", display_name="Bed of Nails", category="Dangerous",
             tooltip="A wooden board attached to the scene.\nIt has many sharp nails on one side.",
             image="BedOfNails", shape=2, width=0.8, height=0.15, mass=0.0, bounciness=0.2, behavior="sharp",
             extra={"SharpAbove": "0.006"},
             polygons=parse_polys("(-0.4,-0.075)=(0.4,-0.075)=(0.4,0.006)=(-0.4,0.006);"
                                  "(-0.34,-0.05)=(0.34,-0.05)=(0.34,0.06)=(-0.34,0.06)")),
        dict(type_name="CircularSaw", display_name="Circular Saw", category="Dangerous",
             tooltip="A light rotating disc with sharp teeth,\ndangerous for balloons and penguins alike.",
             image="CircularSaw", shape=1, width=0.38, height=0.38, mass=0.4, bounciness=0.1,
             behavior="sharp", has_pivot=True, extra={"Spin": "true"}),
        dict(type_name="ColaMintBottle", display_name="Cola+Mint Bottle", category="Machines",
             tooltip="This is a prepared cola bottle with a mint in it.\nIf you shake it just a little bit, a reaction starts,\nwhich makes the bottle spit a long stream of cola.",
             image="ColaBottleNormal;ColaBottleFoaming;ColaBottleBlowing;ColaBottleEmpty", shape=2,
             width=0.166, height=0.5, mass=1.7, bounciness=0.2, behavior="cola_mint",
             polygons=parse_polys("(-0.01,0.25)=(-0.083,0.12)=(-0.075,-0.234)=(-0.060,-0.25)"
                                  "=(0.060,-0.25)=(0.075,-0.234)=(0.083,0.12)=(0.01,0.25)")),
        dict(type_name="Dynamite", display_name="Dynamite", category="Machines",
             tooltip="Dynamite with a phone-activated fuse.\nWhen its detonator box is pushed, it explodes.",
             image="Dynamite;DynamiteRinging;DynamiteActive;DynamiteBoom;Empty", shape=2,
             width=0.43, height=0.32, mass=0.8, bounciness=0.1, behavior="dynamite",
             polygons=parse_polys("(-0.215,-0.16)=(0.215,-0.16)=(0.215,0.02)=(-0.15,0.16)=(-0.215,0.16)")),
        dict(type_name="DetonatorBox", display_name="Detonator Box", category="Machines",
             tooltip="Push the handle down and the dynamite\nwith the matching phone number explodes.",
             image="DetonatorBox;DetonatorBoxActivated;DetonatorBoxRinging;DetonatorBoxDone", shape=0,
             width=0.33, height=0.35, mass=4.0, bounciness=0.0, behavior="detonator"),
        dict(type_name="Spring", display_name="Spring", category="Machines",
             tooltip="A spring. Compress it and it pushes back.",
             image="spring20", shape=0, width=0.4, height=0.2, mass=0.5, bounciness=0.95),
        dict(type_name="CustomBall", display_name="Ball", category="Balls", tooltip="A ball.",
             image="CustomBall", shape=1, width=0.2, height=0.2, mass=1.0, bounciness=0.3),
        dict(type_name="RectObject", display_name="Rectangle", category="Building blocks",
             tooltip="", image="RectObject", shape=0, width=0.5, height=0.1, mass=0.0, bounciness=0.1),
        dict(type_name="PolyObject", display_name="Polygon", category="Building blocks",
             tooltip="", image="PolyObject", shape=2, width=0.5, height=0.5, mass=0.0, bounciness=0.1),
        dict(type_name="Scenery", display_name="Scenery", category="Decoration", tooltip="",
             image="Scenery", shape=3, width=0.5, height=0.5, mass=0.0, no_collision=True, z=1.0),
        dict(type_name="PostItTutorial", display_name="Tutorial Note", category="Notes",
             tooltip="Click me!", image="PostItTutorial", shape=3, width=0.22, height=0.22,
             no_collision=True, behavior="postit", z=10.0),
        dict(type_name="PostItHint", display_name="Hint Note", category="Notes",
             tooltip="Click me!", image="PostItHint", shape=3, width=0.22, height=0.22,
             no_collision=True, behavior="postit", z=10.0),
        dict(type_name="PostItMisc", display_name="Note", category="Notes",
             tooltip="Click me!", image="PostItMisc", shape=3, width=0.22, height=0.22,
             no_collision=True, behavior="postit", z=10.0),
    ]
    for d in defs:
        if isinstance(d.get("polygons"), tuple):
            d["polygons"] = fit_polys(d["polygons"], d["width"], d["height"])
        d.setdefault("category", default_category(d))
    return defs


def gd_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def gd_float(f):
    return repr(float(f))


def write_def(d):
    behavior = d.get("behavior")
    lines = ['[gd_resource type="Resource" script_class="ObjectDef" load_steps=%d format=3]' % (3 if behavior else 2), ""]
    lines.append('[ext_resource type="Script" path="res://scripts/object_def.gd" id="1"]')
    if behavior:
        lines.append('[ext_resource type="Script" path="res://scripts/behaviors/%s.gd" id="2"]' % behavior)
    lines += ["", "[resource]", 'script = ExtResource("1")']
    lines.append("type_name = " + gd_str(d["type_name"]))
    lines.append("display_name = " + gd_str(d["display_name"]))
    lines.append("tooltip = " + gd_str(d.get("tooltip", "")))
    lines.append("category = " + gd_str(d["category"]))
    lines.append("image = " + gd_str(d.get("image", "")))
    z = d.get("z", d.get("extra", {}).get("ZValue", 2.0))
    lines.append("z_value = " + gd_float(z))
    lines.append("shape = %d" % d["shape"])
    lines.append("width = " + gd_float(d["width"]))
    lines.append("height = " + gd_float(d["height"]))
    lines.append("mass = " + gd_float(d.get("mass", 0.0)))
    lines.append("bounciness = " + gd_float(d.get("bounciness", 0.1)))
    fr = d.get("extra", {}).get("Friction")
    lines.append("friction = " + gd_float(fr if fr is not None else 0.3))
    polys = d.get("polygons", [])
    if polys:
        parts = []
        for p in polys:
            parts.append("PackedVector2Array(" + ", ".join("%s, %s" % (gd_float(x), gd_float(y)) for x, y in p) + ")")
        lines.append("polygons = Array[PackedVector2Array]([" + ", ".join(parts) + "])")
    pivot = d.get("extra", {}).get("PivotPoint")
    if pivot or d.get("has_pivot"):
        lines.append("has_pivot = true")
        if pivot:
            x, y = re.findall(r"[-\d.]+", pivot)[:2]
            lines.append("pivot = Vector2(%s, %s)" % (gd_float(x), gd_float(y)))
    if d.get("no_collision"):
        lines.append("no_collision = true")
    lines.append("resizable = " + gd_str(d.get("resizable", "none")))
    if behavior:
        lines.append('behavior = ExtResource("2")')
    extra = {k: v for k, v in d.get("extra", {}).items() if k not in ("Friction", "PivotPoint", "ZValue")}
    if d.get("behavior") == "sharp" and "SharpAbove" in d.get("extra", {}):
        pass
    if extra:
        lines.append("extra = {" + ", ".join("%s: %s" % (gd_str(k), gd_str(v)) for k, v in extra.items()) + "}")
    path = os.path.join(OUT, d["type_name"] + ".tres")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    tbe = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(ROOT), "tbe-original")
    os.makedirs(OUT, exist_ok=True)
    all_defs = collect(tbe)
    for d in all_defs:
        write_def(d)
    print("wrote %d object definitions" % len(all_defs))
    for d in all_defs:
        print("  %-22s %-16s %.3fx%.3f m=%s" % (d["type_name"], d["category"], d["width"], d["height"], d.get("mass", 0)))
