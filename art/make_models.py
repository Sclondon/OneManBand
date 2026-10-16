# Builds the bandsman, his instruments and the bandstand as low-poly, vertex-coloured models
# (no textures, a few hundred faces each, limbs as separate rigid pieces the way an N64 character
# was), and writes them out as .glb for the game and .blend to look at.
#
#   blender --background --python art/make_models.py -- <project folder>
#
# Everything is laid out standing at rest in Blender's own space: Z up, the man facing -Y, his
# left hand at +X. Each Part is an object whose origin is the joint it turns about.

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = sys.argv[sys.argv.index("--") + 1]

PURPLE = "#7446ad"
PURPLE_D = "#43266b"
PURPLE_L = "#9263c9"
GOLD = "#f0c23a"
GOLD_D = "#b98614"
SKIN = "#ddd6b8"
SKIN_D = "#b3a586"
HAIR = "#e86a1c"
HAIR_D = "#b0440e"
WHITE = "#f4f0e2"
SHIRT = "#f1e6c6"
SHIRT_D = "#d9c9a0"
RED = "#cf3a30"
RED_D = "#8a1d1c"
BROWN = "#80502a"
BROWN_D = "#4d2d15"
WOOD = "#b98344"
WOOD_L = "#d7a865"
CREAM = "#f0e4bf"
BRASS = "#f0c046"
BRASS_D = "#a8741a"
TEAL = "#33b3a6"
TEAL_D = "#1d7a78"
BLUE = "#3565c4"
BLUE_D = "#1f3d80"
DARK = "#231a2b"
GREEN = "#5fa53a"
GREEN_L = "#86c24c"
GREEN_D = "#356f2a"
GREEN_DD = "#234f26"
DIRT = "#b89b63"
STONE = "#b8a583"
STONE_D = "#84745c"
LAMP = "#ffe07a"

PARTS = []


def lin(c):
    c = c.lstrip("#")
    out = []
    for i in (0, 2, 4):
        v = int(c[i:i + 2], 16) / 255.0
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


class Part:
    def __init__(self, name, parent=None, pivot=(0, 0, 0)):
        self.name = name
        self.parent = parent
        self.pivot = Vector(pivot)
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.uv = None
        self.obj = None
        PARTS.append(self)

    # Colours the new faces from c1 at p1 to c2 at p2; faces square to `axis` stay flat
    def _finish(self, verts, c1, c2, p1, p2, axis=None, flat=False):
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        bmesh.ops.recalc_face_normals(self.bm, faces=list(faces))
        self.bm.normal_update()
        a = Vector(p1)
        d = Vector(p2) - a
        dd = d.length_squared or 1.0
        c1 = lin(c1)
        c2 = lin(c2) if c2 else c1
        for f in faces:
            f.smooth = not flat and (axis is None or abs(f.normal.dot(axis)) < 0.9)
            for l in f.loops:
                t = max(0.0, min(1.0, (l.vert.co - a).dot(d) / dd))
                l[self.col] = mix(c1, c2, t)

    # A tube or cone from p1 (radius r1) to p2 (radius r2); `flat` squashes it front to back
    # With `caps` off it is an open pipe, and `facing` says which way its skin looks:
    # 1 out from its middle, -1 in toward it.
    def cyl(self, p1, p2, r1, r2, c1, c2=None, seg=6, flat=1.0, caps=True, facing=1):
        p1 = Vector(p1)
        p2 = Vector(p2)
        d = p2 - p1
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        m = Matrix.Translation((p1 + p2) / 2) @ rot @ Matrix.Diagonal((1, flat, 1, 1))
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=seg,
                                    radius1=r1, radius2=r2, depth=d.length, matrix=m)
        self._finish(res["verts"], c1, c2, p1, p2, d.normalized())
        if not caps:
            axis = d.normalized()
            faces = set()
            for v in res["verts"]:
                faces.update(v.link_faces)
            for f in faces:
                mid = f.calc_center_median() - p1
                if f.normal.dot(mid - axis * mid.dot(axis)) * facing < 0:
                    f.normal_flip()
        return self

    # The bell of a horn, hollow: an open cone from the throat at p1 (radius r1) out to the
    # mouth at p2 (radius r2), a darker cone inside it that goes black toward the throat, and
    # a lip joining the two round the mouth
    def horn(self, p1, p2, r1, r2, c1, c2=None, seg=8, inside="#5e3f10", thick=0.9):
        p1 = Vector(p1)
        p2 = Vector(p2)
        d = (p2 - p1).normalized()
        self.cyl(p1, p2, r1, r2, c1, c2, seg=seg, caps=False)
        self.cyl(p1, p2, r1 * 0.6, r2 * thick, "#120b10", inside, seg=seg, caps=False, facing=-1)
        self.cyl(p2 - d * 0.0005, p2 + d * 0.0005, r2 * thick, r2, c2 or c1, seg=seg, caps=False)
        self.cyl(p1 - d * 0.001, p1 + d * 0.001, r1 * 0.6, r1 * 0.6, "#120b10", seg=seg)
        return self

    # A line of tubes through the points
    def pipe(self, points, r, c1, c2=None, seg=5):
        for i in range(len(points) - 1):
            self.cyl(points[i], points[i + 1], r, r, c1, c2, seg)
            self.ball(points[i + 1], r, c2 or c1, seg=seg, rings=3)
        return self

    # `c1` on top, `c2` (if any) underneath
    def ball(self, c, r, c1, c2=None, seg=8, rings=5):
        c = Vector(c)
        if not isinstance(r, tuple):
            r = (r, r, r)
        m = Matrix.Translation(c) @ Matrix.Diagonal((r[0], r[1], r[2], 1))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=1.0, matrix=m)
        self._finish(res["verts"], c2 or c1, c1, c - Vector((0, 0, r[2])), c + Vector((0, 0, r[2])))
        return res["verts"]

    def box(self, c, size, c1, c2=None, rot=None):
        c = Vector(c)
        m = Matrix.Translation(c)
        if rot:
            m = m @ Euler(rot).to_matrix().to_4x4()
        m = m @ Matrix.Diagonal((size[0], size[1], size[2], 1))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        h = Vector((0, 0, size[2] / 2))
        self._finish(res["verts"], c2 or c1, c1, c - h, c + h, flat=True)
        return self

    # Makes all of it so many times the size, about its own origin
    def resize(self, k):
        bmesh.ops.scale(self.bm, vec=(k, k, k), verts=self.bm.verts)

    def make(self, scene):
        bmesh.ops.translate(self.bm, verts=self.bm.verts, vec=-self.pivot)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        mesh.color_attributes.render_color_index = 0
        self.obj = bpy.data.objects.new(self.name, mesh)
        scene.collection.objects.link(self.obj)
        if self.parent:
            self.obj.parent = self.parent.obj
            self.obj.location = self.pivot - self.parent.pivot
        else:
            self.obj.location = self.pivot


def write(name):
    scene = bpy.context.scene
    for p in PARTS:
        p.make(scene)
    PARTS.clear()
    os.makedirs(os.path.join(ROOT, "models"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "art", name + ".blend"))
    want = dict(filepath=os.path.join(ROOT, "models", name + ".glb"), export_format="GLB",
                export_yup=True, export_animations=False, export_vertex_color="ACTIVE",
                export_all_vertex_colors=False, export_active_vertex_color_when_no_material=True)
    known = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    bpy.ops.export_scene.gltf(**{k: v for k, v in want.items() if k in known})
    print("wrote", name, "faces:", sum(len(o.data.polygons) for o in scene.objects if o.type == "MESH"))


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# A drum standing on the axis p1..p2: shell, two hoops and two skins
def drum(part, p1, p2, r, shell, seg=10):
    p1 = Vector(p1)
    p2 = Vector(p2)
    d = (p2 - p1).normalized()
    hoop = 0.035 * (r / 0.3) + 0.012
    part.cyl(p1, p2, r, r, shell, seg=seg)
    part.cyl(p1 - d * 0.004, p1 + d * hoop, r * 1.045, r * 1.045, GOLD, seg=seg)
    part.cyl(p2 - d * hoop, p2 + d * 0.004, r * 1.045, r * 1.045, GOLD, seg=seg)
    part.cyl(p1 - d * 0.009, p1, r * 0.94, r * 0.94, CREAM, seg=seg)
    part.cyl(p2, p2 + d * 0.009, r * 0.94, r * 0.94, CREAM, seg=seg)


def build_bandsman():
    fresh()

    # Overalls over a shirt: the seat and legs, a band round the waist, a bib and two straps
    hips = Part("hips", None, (0, 0, 0.95))
    hips.ball((0, 0, 0.95), (0.195, 0.145, 0.14), PURPLE, PURPLE_D)

    torso = Part("torso", hips, (0, 0, 1.0))
    torso.cyl((0, 0, 0.98), (0, 0, 1.42), 0.185, 0.215, SHIRT_D, SHIRT, seg=8, flat=0.68)
    torso.ball((0, 0, 1.42), (0.215, 0.146, 0.07), SHIRT)
    torso.cyl((0, 0, 0.96), (0, 0, 1.15), 0.2, 0.2, PURPLE, seg=8, flat=0.72)
    torso.box((0, -0.14, 1.24), (0.25, 0.045, 0.26), PURPLE_L, PURPLE)
    torso.box((0, -0.166, 1.25), (0.13, 0.012, 0.1), PURPLE_D)
    torso.box((0, 0.135, 1.22), (0.2, 0.04, 0.2), PURPLE, PURPLE_D)
    for s in (1, -1):
        torso.pipe([(0.095 * s, -0.16, 1.35), (0.085 * s, -0.125, 1.46), (0.08 * s, 0.03, 1.5),
                    (0.07 * s, 0.14, 1.3)], 0.024, PURPLE, seg=4)
        torso.ball((0.095 * s, -0.172, 1.34), 0.024, GOLD, GOLD_D, seg=5, rings=3)
    torso.cyl((0, 0, 1.44), (0, 0, 1.54), 0.09, 0.065, WHITE, seg=6)
    torso.cyl((0, -0.105, 1.47), (0.1, -0.11, 1.47), 0.012, 0.05, RED, RED_D, seg=4)
    torso.cyl((0, -0.105, 1.47), (-0.1, -0.11, 1.47), 0.012, 0.05, RED, RED_D, seg=4)
    torso.ball((0, -0.11, 1.47), 0.022, RED_D, seg=5, rings=3)

    head = Part("head", torso, (0, 0, 1.5))
    head.ball((0, 0.035, 1.735), (0.16, 0.165, 0.15), HAIR, HAIR_D)
    head.cyl((-0.07, -0.09, 1.83), (0.11, -0.13, 1.875), 0.055, 0.012, HAIR, HAIR_D)
    head.cyl((0.03, -0.05, 1.86), (0.15, -0.04, 1.84), 0.05, 0.01, HAIR, HAIR_D)
    for s in (1, -1):
        head.cyl((0.14 * s, -0.04, 1.73), (0.132 * s, -0.065, 1.6), 0.03, 0.006, HAIR_D)
        head.ball((0.142 * s, 0.0, 1.67), (0.02, 0.035, 0.05), SKIN_D, seg=5, rings=3)
    head.cyl((0, 0.15, 1.66), (0, 0.25, 1.58), 0.07, 0.008, HAIR_D)
    head.cyl((0, -0.13, 1.665), (0, -0.225, 1.64), 0.03, 0.004, "#c4b48f", seg=5)
    # A little fez, worn at an angle
    head.cyl((-0.05, 0.0, 1.855), (-0.075, 0.01, 1.975), 0.078, 0.056, RED, RED_D)
    head.cyl((-0.048, 0.0, 1.85), (-0.053, 0.002, 1.875), 0.083, 0.08, GOLD)
    head.cyl((-0.075, 0.01, 1.975), (-0.16, 0.0, 1.9), 0.006, 0.006, GOLD, seg=4)
    head.ball((-0.16, 0.0, 1.89), 0.02, GOLD, GOLD_D, seg=5, rings=3)

    # The skin of the head is its own piece, so the game can lay a painted face over it
    face = Part("face", head, (0, 0, 1.5))
    centre = Vector((0, 0, 1.67))
    size = Vector((0.145, 0.15, 0.185))
    verts = face.ball(centre, tuple(size), SKIN, "#cbc2a0", seg=10, rings=7)
    for v in verts:
        low = max(0.0, (centre.z - v.co.z) / size.z)
        k = 1.0 - 0.38 * low ** 1.3
        v.co.x = centre.x + (v.co.x - centre.x) * k
        v.co.y = centre.y + (v.co.y - centre.y) * k - 0.02 * low
    face.uv = face.bm.loops.layers.uv.new("UVMap")
    for f in face.bm.faces:
        front = all(v.co.y < centre.y - 0.03 for v in f.verts)
        for l in f.loops:
            if front:
                l[face.uv].uv = ((l.vert.co.x - centre.x) / (2 * size.x) + 0.5,
                                 (l.vert.co.z - (centre.z - size.z)) / (2 * size.z))
            else:
                l[face.uv].uv = (0.008, 0.992)

    for s, side in ((1, "L"), (-1, "R")):
        x = 0.26 * s
        up = Part("upper_" + side, torso, (x, 0, 1.42))
        up.ball((x, 0, 1.42), 0.068, SHIRT, seg=6, rings=4)
        up.cyl((x, 0, 1.12), (x, 0, 1.42), 0.05, 0.06, SHIRT_D, SHIRT)
        fo = Part("fore_" + side, up, (x, 0, 1.12))
        fo.ball((x, 0, 1.12), 0.052, SHIRT_D, seg=6, rings=4)
        fo.cyl((x, 0, 0.88), (x, 0, 1.12), 0.042, 0.05, SHIRT, SHIRT_D)
        fo.cyl((x, 0, 0.855), (x, 0, 0.9), 0.052, 0.05, GOLD)
        ha = Part("hand_" + side, fo, (x, 0, 0.86))
        ha.ball((x, 0, 0.81), (0.04, 0.032, 0.055), SKIN, SKIN_D, seg=6, rings=4)
        ha.ball((x, -0.03, 0.83), 0.018, SKIN, seg=5, rings=3)
        # (fingers a joint too long)
        for k in range(4):
            ha.cyl((x - 0.03 + k * 0.02, -0.005, 0.775), (x - 0.036 + k * 0.024, -0.012, 0.675), 0.011, 0.003, SKIN, SKIN_D, seg=4)

        x = 0.1 * s
        th = Part("thigh_" + side, hips, (x, 0, 0.92))
        th.cyl((x, 0, 0.5), (x, 0, 0.92), 0.07, 0.092, PURPLE_D, PURPLE)
        sh = Part("shin_" + side, th, (x, 0, 0.5))
        sh.ball((x, 0, 0.5), 0.072, PURPLE_D, seg=6, rings=4)
        sh.cyl((x, 0, 0.19), (x, 0, 0.5), 0.062, 0.07, PURPLE_D)
        sh.cyl((x, 0, 0.17), (x, 0, 0.22), 0.07, 0.068, PURPLE_L)
        sh.cyl((x, 0, 0.09), (x, 0, 0.19), 0.04, 0.042, WHITE)
        ft = Part("foot_" + side, sh, (x, 0, 0.1))
        ft.ball((x, -0.06, 0.05), (0.064, 0.13, 0.05), BROWN, BROWN_D, seg=6, rings=4)
        ft.cyl((x, -0.16, 0.05), (x, -0.25, 0.14), 0.036, 0.004, BROWN)

    # The rig on his back: a frame, and everything that hangs off it
    pack = Part("pack", torso, (0, 0.2, 1.2))
    for s in (1, -1):
        pack.cyl((0.2 * s, 0.17, 0.92), (0.2 * s, 0.17, 2.12), 0.018, 0.018, BROWN_D, BROWN, seg=5)
        pack.pipe([(0.13 * s, -0.142, 1.2), (0.13 * s, -0.11, 1.44), (0.13 * s, 0.02, 1.5),
                   (0.14 * s, 0.17, 1.42)], 0.02, BROWN, seg=4)
    for z in (1.02, 2.08):
        pack.cyl((-0.22, 0.17, z), (0.22, 0.17, z), 0.015, 0.015, BROWN, seg=5)
    pack.cyl((-0.2, 0.17, 2.1), (-0.2, 0.17, 2.3), 0.01, 0.01, BROWN_D, seg=4)
    pack.cyl((-0.2, 0.17, 2.225), (-0.2, 0.17, 2.26), 0.02, 0.21, BRASS_D, BRASS, seg=10)
    pack.pipe([(-0.2, 0.17, 1.7), (-0.42, 0.19, 1.86), (-0.56, 0.2, 2.02)], 0.012, BROWN_D, seg=4)

    big = Part("pack_drum", pack, (0, 0.4, 1.3))
    drum(big, (0, 0.2, 1.3), (0, 0.6, 1.3), 0.5, RED, seg=14)
    big.cyl((0, 0.609, 1.3), (0, 0.615, 1.3), 0.28, 0.28, GOLD, seg=5)
    big.cyl((0, 0.615, 1.3), (0, 0.62, 1.3), 0.15, 0.15, RED_D, seg=5)

    tom = Part("pack_tom", pack, (-0.42, 0.38, 1.73))
    drum(tom, (-0.38, 0.38, 1.66), (-0.46, 0.38, 1.8), 0.125, BLUE, seg=8)

    hat = Part("cym_top", pack, (-0.2, 0.17, 2.285))
    hat.cyl((-0.2, 0.17, 2.27), (-0.2, 0.17, 2.305), 0.21, 0.02, BRASS, BRASS_D, seg=10)

    crash = Part("cym_crash", pack, (-0.56, 0.2, 2.03))
    crash.cyl((-0.555, 0.2, 2.03), (-0.58, 0.187, 2.072), 0.28, 0.03, BRASS, BRASS_D, seg=10)

    chimes = Part("pack_bells", pack, (0, 0.17, 2.08))
    for x in (-0.15, -0.05, 0.05, 0.15):
        chimes.cyl((x, 0.17, 2.07), (x, 0.17, 2.02), 0.005, 0.005, BROWN_D, seg=4)
        chimes.cyl((x, 0.17, 2.02), (x, 0.17, 1.9), 0.016, 0.07, GOLD, GOLD_D, seg=6)
        chimes.ball((x, 0.17, 1.885), 0.024, GOLD_D, seg=5, rings=3)

    tuba = Part("tuba", pack, (0.52, 0.2, 1.8))
    tuba.pipe([(0.62, 0.3, 0.98), (0.67, 0.42, 1.2), (0.62, 0.3, 1.45), (0.56, 0.22, 1.2),
               (0.5, 0.24, 1.0)], 0.05, BRASS_D, BRASS)
    tuba.cyl((0.62, 0.3, 1.45), (0.52, 0.2, 1.8), 0.06, 0.08, BRASS_D, BRASS, seg=8)
    tuba.horn((0.52, 0.2, 1.8), (0.66, -0.05, 2.4), 0.08, 0.46, BRASS, GOLD, seg=12, thick=0.93)
    # (and a little one growing out of its side, for the high notes)
    tuba.cyl((0.59, 0.25, 1.62), (0.8, 0.3, 1.78), 0.03, 0.035, BRASS_D, BRASS, seg=6)
    tuba.horn((0.8, 0.3, 1.78), (0.92, 0.27, 1.93), 0.035, 0.11, BRASS, GOLD, seg=8)

    # The tuba's mouth pipe only comes round to the front while he is playing it
    lead = Part("tuba_pipe", torso, (0, 0, 1.2))
    lead.pipe([(0.5, 0.24, 1.02), (0.36, -0.06, 1.06), (0.14, -0.2, 1.3), (0.02, -0.2, 1.55)],
              0.016, BRASS_D, BRASS, seg=4)
    lead.cyl((0.02, -0.2, 1.55), (0.0, -0.17, 1.6), 0.012, 0.026, BRASS, seg=5)

    # What he holds. Each is built about its own origin, where the game takes hold of it, and
    # each is far too big, or has grown something it should not have.

    # A long piccolo, played sideways: the lip hole is at the origin, the pipe
    # runs out to his right, and the far end curls up into a horn
    pc = Part("piccolo")
    pc.cyl((0.06, 0, 0), (-0.5, 0, 0), 0.022, 0.02, DARK, seg=6)
    for x in (0.06, -0.06, -0.5):
        pc.cyl((x + 0.01, 0, 0), (x - 0.01, 0, 0), 0.029, 0.029, GOLD, seg=6)
    pc.ball((0.0, -0.005, 0.02), (0.016, 0.014, 0.008), GOLD, seg=5, rings=3)
    for i in range(6):
        pc.ball((-0.12 - i * 0.06, -0.008, 0.021), 0.014, GOLD, seg=4, rings=3)
    pc.pipe([(-0.5, 0, 0), (-0.6, 0, 0.02), (-0.67, 0, 0.1), (-0.66, 0, 0.2)], 0.021, DARK, seg=5)
    pc.horn((-0.66, 0, 0.2), (-0.6, 0, 0.34), 0.025, 0.12, BRASS, GOLD, seg=8)
    for y in (-0.012, 0.012):
        pc.cyl((-0.3, y, -0.02), (-0.3 - y * 3, y * 2, -0.22), 0.022, 0.0, RED, RED_D, seg=4)

    pc.resize(0.85)

    # The trumpet is a bunch of five horns on one mouthpiece, a horn to each note: the lowest
    # is the biggest, and each wears the colour of its button. They are separate pieces so
    # that the one that sounds can jump.
    tr = Part("trumpet")
    tr.cyl((0, 0.0, 0), (0, -0.045, 0), 0.022, 0.009, GOLD, seg=5)
    tr.cyl((0, -0.04, 0), (0, -0.12, 0), 0.013, 0.02, BRASS, seg=5)
    tr.ball((0, -0.13, 0), (0.07, 0.045, 0.045), BRASS, BRASS_D, seg=8, rings=4)
    bands = ["#4fb0ff", "#58d68d", "#f8ca22", "#ff9a3d", "#ff6b7c"]
    for i in range(5):
        # (fanned wide, and every other one lifted, so that no two mouths touch)
        side = (i - 2) * 0.58
        lift = 0.2 if i % 2 == 1 else 0.0
        base = Vector((math.sin(side) * 0.05, -0.14, 0.0))
        out = Vector((math.sin(side), -math.cos(side) * 0.9, 0.12 + lift)).normalized()
        up = Vector((math.sin(side) * 0.9, -math.cos(side) * 0.75, 0.38 + lift)).normalized()
        long = 0.44 - i * 0.035
        mouth = 0.085 - i * 0.008
        elbow = base + out * long * 0.55
        end = elbow + up * long * 0.45
        horn = Part("horn_%d" % i, tr, tuple(base))
        horn.cyl(base, elbow, 0.014, 0.02, BRASS_D, BRASS, seg=5)
        horn.ball(elbow, 0.021, BRASS, seg=5, rings=3)
        horn.horn(elbow, end, 0.02, mouth, BRASS, GOLD, seg=8)
        horn.cyl(end - up * 0.012, end + up * 0.004, mouth * 1.04, mouth * 1.1, bands[i], seg=8, caps=False)

    # An accordion with organ pipes coming out of the top
    al = Part("acc_L")
    al.box((0.07, 0, 0), (0.14, 0.2, 0.46), RED, RED_D)
    al.box((0.146, -0.04, 0), (0.014, 0.09, 0.4), CREAM)
    for i in range(8):
        al.box((0.155, -0.058, -0.168 + i * 0.048), (0.006, 0.05, 0.02), DARK)
    al.box((0.07, 0, 0.235), (0.146, 0.206, 0.018), GOLD)
    al.box((0.07, 0, -0.235), (0.146, 0.206, 0.018), GOLD)
    for y, h in ((-0.05, 0.2), (0.05, 0.32)):
        al.cyl((0.07, y, 0.24), (0.07, y, 0.24 + h), 0.03, 0.03, BRASS_D, GOLD, seg=6)
        al.cyl((0.07, y, 0.24 + h), (0.07, y, 0.26 + h), 0.03, 0.04, GOLD, seg=6)
    ar = Part("acc_R")
    ar.box((-0.07, 0, 0), (0.14, 0.2, 0.46), RED, RED_D)
    for i in range(5):
        for j in range(2):
            ar.ball((-0.144, -0.035 + j * 0.06, -0.14 + i * 0.07), 0.018, CREAM, seg=4, rings=3)
    ar.box((-0.07, 0, 0.235), (0.146, 0.206, 0.018), GOLD)
    ar.box((-0.07, 0, -0.235), (0.146, 0.206, 0.018), GOLD)
    for y, h in ((-0.06, 0.16), (0.0, 0.27), (0.06, 0.38)):
        ar.cyl((-0.07, y, 0.24), (-0.07, y, 0.24 + h), 0.026, 0.026, BRASS_D, GOLD, seg=6)
        ar.cyl((-0.07, y, 0.24 + h), (-0.07, y, 0.26 + h), 0.026, 0.036, GOLD, seg=6)
    # One unit wide, for the game to stretch
    ab = Part("acc_bellows")
    for i in range(6):
        x = (i + 0.5) / 6.0 - 0.5
        ab.box((x, 0, 0), (1 / 6.0, 0.15, 0.4), DARK)
        ab.box((x, 0, 0), (1 / 15.0, 0.19, 0.45), CREAM)

    # A big guitar
    gt = Part("guitar")
    gt.cyl((0, -0.05, 0), (0, 0.05, 0), 0.25, 0.25, WOOD, BROWN, seg=10)
    gt.cyl((0.27, -0.05, 0), (0.27, 0.05, 0), 0.18, 0.18, WOOD, BROWN, seg=10)
    gt.cyl((0, -0.058, 0), (0, -0.05, 0), 0.232, 0.232, WOOD_L, seg=10)
    gt.cyl((0.27, -0.058, 0), (0.27, -0.05, 0), 0.165, 0.165, WOOD_L, seg=10)
    gt.cyl((0.14, -0.065, 0), (0.14, -0.057, 0), 0.07, 0.07, DARK, seg=8)
    gt.box((0.72, -0.04, 0), (0.62, 0.04, 0.06), BROWN_D)
    gt.box((1.08, -0.04, 0), (0.14, 0.04, 0.1), BROWN)
    gt.ball((1.17, -0.045, 0.04), 0.055, BROWN, BROWN_D, seg=6, rings=4)
    for i in range(4):
        gt.ball((1.04 + (i % 2) * 0.07, -0.04, 0.065 if i < 2 else -0.065), 0.02, GOLD, seg=4, rings=3)
    gt.box((-0.12, -0.066, 0), (0.03, 0.016, 0.14), BROWN_D)
    gt.box((0.48, -0.068, 0), (1.2, 0.005, 0.04), CREAM)

    gt.resize(0.8)

    # A ukulele: the guitar again, small and pale, with four pegs
    uk = Part("ukulele")
    uk.cyl((0, -0.04, 0), (0, 0.04, 0), 0.15, 0.15, WOOD_L, WOOD, seg=10)
    uk.cyl((0.17, -0.04, 0), (0.17, 0.04, 0), 0.115, 0.115, WOOD_L, WOOD, seg=10)
    uk.cyl((0, -0.046, 0), (0, -0.04, 0), 0.138, 0.138, "#f2d29a", seg=10)
    uk.cyl((0.17, -0.046, 0), (0.17, -0.04, 0), 0.104, 0.104, "#f2d29a", seg=10)
    uk.cyl((0.09, -0.052, 0), (0.09, -0.045, 0), 0.045, 0.045, DARK, seg=8)
    uk.box((0.4, -0.03, 0), (0.3, 0.03, 0.045), BROWN)
    uk.box((0.6, -0.03, 0), (0.1, 0.03, 0.075), BROWN_D)
    for i in range(4):
        uk.ball((0.575 + (i % 2) * 0.05, -0.03, 0.048 if i < 2 else -0.048), 0.016, CREAM, seg=4, rings=3)
    uk.box((-0.075, -0.052, 0), (0.024, 0.012, 0.09), BROWN_D)
    uk.box((0.27, -0.054, 0), (0.7, 0.004, 0.03), WHITE)

    # An electric guitar, solid and red: a body with two horns, a white scratchplate, two
    # pickups, knobs, and a long neck with all six pegs up one side of its head
    el = Part("electric")
    el.cyl((0, -0.035, 0), (0, 0.035, 0), 0.21, 0.21, RED, RED_D, seg=10)
    el.cyl((0.2, -0.035, 0), (0.2, 0.035, 0), 0.15, 0.15, RED, RED_D, seg=10)
    for z, l in ((0.12, 0.2), (-0.11, 0.13)):
        el.box((0.32, 0, z), (l, 0.07, 0.07), RED, RED_D, rot=(0, -0.5 if z > 0 else 0.4, 0))
    el.cyl((0.03, -0.041, 0.04), (0.03, -0.035, 0.04), 0.14, 0.14, WHITE, seg=8)
    for x in (0.02, 0.15):
        el.box((x, -0.046, 0), (0.035, 0.01, 0.09), DARK)
        for z in (-0.03, 0.0, 0.03):
            el.ball((x, -0.051, z), 0.006, "#c9ccd4", seg=4, rings=2)
    el.box((-0.1, -0.044, 0), (0.03, 0.012, 0.11), "#c9ccd4")
    for x, z in ((-0.08, -0.13), (-0.02, -0.15), (0.04, -0.15)):
        el.cyl((x, -0.035, z), (x, -0.06, z), 0.018, 0.016, GOLD, GOLD_D, seg=6)
    el.box((0.62, -0.03, 0), (0.62, 0.035, 0.05), BROWN)
    for i in range(6):
        el.box((0.38 + i * 0.09, -0.049, 0), (0.004, 0.004, 0.05), "#c9ccd4")
    el.box((1.0, -0.03, 0.02), (0.18, 0.025, 0.09), RED, RED_D)
    for i in range(6):
        el.ball((0.93 + i * 0.03, -0.03, 0.075), 0.012, "#c9ccd4", seg=4, rings=3)
    el.box((0.42, -0.053, 0), (1.15, 0.003, 0.032), WHITE)

    el.resize(0.85)

    # A little pipe organ, hung in front of him: a wine-red case with the keys along his side of
    # its top, and beyond them a rank of open brass pipes, tall at the ends and short in the
    # middle so that his face shows over them. (his side is +y, up is +z)
    og = Part("organ")
    og.box((0, 0, 0), (0.6, 0.22, 0.13), "#8c2a3e", "#571624")
    og.box((0, 0, -0.07), (0.64, 0.25, 0.025), GOLD, GOLD_D)
    og.box((0, 0.045, 0.068), (0.5, 0.1, 0.012), WHITE)
    for i in range(11):
        if i % 7 in (2, 6):
            continue
        og.box((-0.2125 + i * 0.0425, 0.03, 0.078), (0.02, 0.06, 0.012), DARK)
    for i in range(5):
        og.ball((-0.2 + i * 0.1, -0.115, 0.01), 0.02, CREAM, GOLD_D, seg=5, rings=3)
    # (two towers of pipes with a low run between them)
    for i in range(9):
        x = -0.26 + i * 0.065
        tall = [0.1, 0.13, 0.24, 0.48, 0.72][abs(i - 4)]
        wide = 0.022 + abs(i - 4) * 0.004
        og.horn((x, -0.055, 0.06), (x, -0.055, 0.06 + tall), wide, wide, BRASS, BRASS_D, seg=7)
        og.cyl((x, -0.055, 0.04), (x, -0.055, 0.075), wide * 0.6, wide, BRASS_D, seg=6)
        og.box((x, -0.055 - wide, 0.115), (wide * 1.2, 0.012, 0.022), DARK)

    # A piano to carry: a long black case with a full run of white and black keys along his side
    # of its top and a gold name strip. (his side is +y, up is +z)
    pn = Part("piano")
    pn.box((0, 0, 0), (0.86, 0.24, 0.09), "#2a2230", DARK)
    pn.box((0, 0.045, 0.047), (0.8, 0.13, 0.008), WHITE)
    for i in range(22):
        pn.box((-0.39 + i * 0.0364 + 0.018, 0.045, 0.052), (0.003, 0.13, 0.004), "#b9b2a0")
    for i in range(21):
        if i % 7 in (2, 6):
            continue
        pn.box((-0.39 + (i + 1) * 0.0364, 0.025, 0.06), (0.02, 0.08, 0.014), DARK)
    pn.box((0, -0.085, 0.05), (0.84, 0.06, 0.02), "#2a2230")
    pn.box((0, -0.06, 0.062), (0.3, 0.008, 0.014), GOLD, GOLD_D)
    for x in (-0.38, 0.38):
        pn.box((x, 0, 0), (0.04, 0.25, 0.1), "#3b3044", DARK)

    # A theremin: a box of valves on a tray, a rod to play the note on and a loop for how loud
    th = Part("theremin")
    th.box((0, 0, 0), (0.38, 0.2, 0.13), WOOD, BROWN)
    th.box((0, -0.101, 0), (0.3, 0.006, 0.08), BROWN_D)
    for x in (-0.08, 0.0, 0.08):
        th.ball((x, -0.106, 0.0), 0.022, GOLD, GOLD_D, seg=5, rings=3)
    th.cyl((0.2, 0, 0.065), (0.2, 0, 0.62), 0.009, 0.007, WHITE, seg=5)
    th.ball((0.2, 0, 0.63), 0.022, WHITE, seg=5, rings=3)
    th.pipe([(-0.19, 0, 0.03), (-0.3, 0.07, 0.03), (-0.4, 0, 0.03), (-0.3, -0.07, 0.03), (-0.19, 0, 0.03)],
            0.009, BRASS_D, BRASS, seg=4)
    for x in (-0.07, 0.05):
        th.cyl((x, 0.03, 0.065), (x, 0.03, 0.16), 0.03, 0.022, "#ffe9a8", LAMP, seg=6)
        th.ball((x, 0.03, 0.165), 0.024, LAMP, seg=5, rings=3)

    # A viola, played under the chin, and its bow
    va = Part("viola")
    va.cyl((0, -0.028, 0), (0, 0.028, 0), 0.125, 0.125, "#a4521f", BROWN_D, seg=10)
    va.cyl((0.17, -0.028, 0), (0.17, 0.028, 0), 0.1, 0.1, "#a4521f", BROWN_D, seg=10)
    va.cyl((0, -0.034, 0), (0, -0.028, 0), 0.114, 0.114, "#c8743a", seg=10)
    va.cyl((0.17, -0.034, 0), (0.17, -0.028, 0), 0.09, 0.09, "#c8743a", seg=10)
    va.box((0.38, -0.02, 0), (0.26, 0.026, 0.034), DARK)
    va.ball((0.53, -0.02, 0), 0.034, BROWN_D, seg=6, rings=4)
    for s in (1, -1):
        va.ball((0.5, -0.02, 0.035 * s), 0.014, DARK, seg=4, rings=3)
        va.box((0.08, -0.037, 0.055 * s), (0.07, 0.004, 0.012), DARK, rot=(0, 0.25 * s, 0))
    va.box((0.2, -0.04, 0), (0.56, 0.004, 0.022), CREAM)
    va.box((-0.02, -0.043, 0), (0.014, 0.014, 0.06), "#e8c890")
    va.ball((-0.1, -0.036, 0.06), (0.05, 0.012, 0.04), DARK, seg=6, rings=3)

    bw = Part("bow")
    bw.cyl((0, 0.06, 0), (0, -0.56, 0), 0.009, 0.006, BROWN_D, BROWN, seg=5)
    bw.box((0, -0.25, -0.022), (0.014, 0.58, 0.004), WHITE)
    bw.box((0, 0.03, -0.012), (0.02, 0.05, 0.026), DARK)
    bw.box((0, -0.55, -0.012), (0.012, 0.02, 0.024), BROWN_D)

    hb = Part("bell_hand")
    hb.cyl((0, 0.06, 0), (0, -0.1, 0), 0.02, 0.02, BROWN, seg=5)
    hb.horn((0, -0.1, 0), (0, -0.33, 0), 0.035, 0.16, GOLD, GOLD_D, seg=8)
    hb.cyl((0, -0.12, 0), (0, -0.3, 0), 0.006, 0.006, GOLD_D, seg=4)
    hb.ball((0, -0.31, 0), 0.042, GOLD_D, seg=5, rings=3)

    hb.resize(0.75)

    # Mallets with heads like toffee apples
    st = Part("stick")
    st.cyl((0, 0.06, 0), (0, -0.36, 0), 0.016, 0.012, CREAM, seg=5)
    st.ball((0, -0.39, 0), 0.045, RED, RED_D, seg=6, rings=4)

    # A bassoon: a long maroon tube doubled back on itself in the boot at its foot, a bell at the
    # top, and the thin silver crook that comes round from it to his mouth. (up is +z, his side +y)
    bn = Part("bassoon")
    bn.cyl((0, 0, -0.5), (0, 0, 0.5), 0.05, 0.036, "#8a3324", "#5a1c14", seg=7)
    bn.cyl((0, 0, -0.56), (0, 0, -0.36), 0.066, 0.06, "#6a2418", "#421109", seg=7)
    bn.cyl((0, 0, -0.58), (0, 0, -0.56), 0.07, 0.07, "#c9ccd4", seg=7)
    bn.cyl((0.055, 0, -0.38), (0.045, 0, 0.3), 0.03, 0.022, "#8a3324", "#5a1c14", seg=6)
    bn.horn((0, 0, 0.5), (0, 0, 0.74), 0.038, 0.075, "#8a3324", "#5a1c14", seg=8)
    bn.cyl((0, 0, 0.49), (0, 0, 0.52), 0.045, 0.045, CREAM, seg=7)
    bn.pipe([(0.045, 0, 0.3), (-0.05, 0.02, 0.41), (-0.17, 0.06, 0.4), (-0.25, 0.09, 0.315)], 0.008, "#c9ccd4", seg=4)
    bn.cyl((-0.25, 0.09, 0.315), (-0.275, 0.1, 0.29), 0.012, 0.004, CREAM, seg=4)
    for i in range(6):
        bn.ball((0.0, -0.045, -0.24 + i * 0.11), 0.017, "#c9ccd4", seg=5, rings=3)

    # The baton he conducts the choir with: a white stick with a cork to hold it by
    bt = Part("baton")
    bt.cyl((0, 0.04, 0), (0, -0.36, 0), 0.011, 0.004, WHITE, seg=5)
    bt.ball((0, 0.05, 0), 0.024, BROWN, BROWN_D, seg=5, rings=3)

    sn = Part("snare")
    drum(sn, (0, 0, -0.07), (0, 0, 0.07), 0.2, BLUE, seg=10)
    st.resize(0.85)

    write("bandsman")


def tree(part, x, y, s, pine, rnd):
    part.cyl((x, y, 0), (x, y, 1.3 * s), 0.2 * s, 0.13 * s, BROWN_D, BROWN, seg=5)
    if pine:
        for i in range(3):
            z = (0.9 + i * 0.75) * s
            part.cyl((x, y, z), (x, y, z + 1.25 * s), (1.15 - i * 0.28) * s, 0.0, "#101f18", "#1f3d28", seg=6)
    else:
        # (October: what leaves are left have turned)
        part.ball((x, y, 2.1 * s), (1.2 * s, 1.2 * s, 1.0 * s), "#e0892a", "#8a3414", seg=6, rings=4)
        part.ball((x + 0.6 * s, y - 0.2 * s, 1.75 * s), 0.7 * s, "#c8571e", "#6e2410", seg=6, rings=4)
        part.ball((x - 0.65 * s, y + 0.1 * s, 1.8 * s), 0.65 * s, "#d9a020", "#8a4a14", seg=6, rings=4)


def build_stage():
    fresh()
    rnd = random.Random(7)

    # The green: rings of grass round a worn patch of dirt, lifting a little toward the edge
    ground = Part("ground")
    bm = ground.bm
    radii = [0.0, 2.3, 3.3, 5.5, 9.0, 14.0, 22.0, 34.0]
    tones = [DIRT, DIRT, "#8a8f3e", "#6f7d36", "#5e6e30", "#465a2a", "#34482a", "#22321f"]
    seg = 18
    rings = []
    shade = {}
    for i, r in enumerate(radii):
        ring = []
        for k in range(1 if i == 0 else seg):
            a = math.tau * k / seg + i * 0.17
            z = 0.0 if r < 6 else ((r - 6) / 28.0) ** 2 * 5.0 + rnd.uniform(-0.2, 0.2)
            v = bm.verts.new((math.cos(a) * r, math.sin(a) * r, z))
            j = rnd.uniform(0.86, 1.1)
            c = lin(tones[i])
            shade[v] = (c[0] * j, c[1] * j, c[2] * j, 1.0)
            ring.append(v)
        rings.append(ring)
    for k in range(seg):
        bm.faces.new((rings[0][0], rings[1][k], rings[1][(k + 1) % seg]))
    for i in range(1, len(rings) - 1):
        for k in range(seg):
            n = (k + 1) % seg
            bm.faces.new((rings[i][k], rings[i + 1][k], rings[i + 1][n], rings[i][n]))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
        f.smooth = True
        for l in f.loops:
            l[ground.col] = shade[l.vert]

    stand = Part("bandstand")
    stand.cyl((0, 0, 0), (0, 0, 0.1), 2.25, 2.2, BROWN_D, BROWN, seg=12)
    stand.cyl((0, 0, 0.1), (0, 0, 0.22), 1.9, 1.9, BROWN, WOOD, seg=12)
    stand.cyl((0, 0, 0.22), (0, 0, 0.225), 1.82, 1.82, WOOD_L, seg=12)
    stand.cyl((0, 0, 0.225), (0, 0, 0.228), 1.1, 1.1, WOOD, seg=12)
    # Posts and a patchwork curtain behind
    for s in (1, -1):
        stand.cyl((2.4 * s, 1.7, 0), (2.4 * s, 1.7, 3.5), 0.1, 0.07, BROWN_D, BROWN, seg=6)
        stand.cyl((2.4 * s, 1.7, 3.5), (2.4 * s, 1.7, 3.62), 0.14, 0.1, GOLD_D, GOLD, seg=6)
    stand.cyl((-2.5, 1.7, 3.2), (2.5, 1.7, 3.2), 0.05, 0.05, BROWN, seg=5)
    cloth = ["#a81f1f", "#1c1622", "#a81f1f", "#1c1622", "#a81f1f", "#1c1622"]
    under = ["#3f0b0e", "#0b080e", "#3f0b0e", "#0b080e", "#3f0b0e", "#0b080e"]
    for i in range(6):
        x = -2.0 + i * 0.8
        stand.box((x, 1.72 + (i % 2) * 0.04, 1.85), (0.82, 0.04, 2.7), cloth[i], under[i])
        stand.cyl((x, 1.66, 3.2), (x, 1.66, 2.82), 0.4, 0.0, GOLD, GOLD_D, seg=4)
    # A barrel, a crate, and a hat for coins
    stand.cyl((4.2, 0.2, 0), (4.2, 0.2, 0.85), 0.34, 0.34, BROWN, WOOD, seg=8)
    for z in (0.15, 0.7):
        stand.cyl((4.2, 0.2, z), (4.2, 0.2, z + 0.06), 0.355, 0.355, STONE_D, seg=8)
    stand.box((-4.3, 0.3, 0.35), (0.7, 0.7, 0.7), WOOD, BROWN, rot=(0, 0, 0.4))
    stand.box((-4.2, 0.35, 0.9), (0.45, 0.45, 0.4), WOOD_L, BROWN, rot=(0, 0, -0.3))
    stand.cyl((0.9, -1.87, 0.1), (0.9, -1.87, 0.29), 0.13, 0.15, DARK, seg=8)
    stand.cyl((0.9, -1.87, 0.1), (0.9, -1.87, 0.112), 0.24, 0.24, DARK, seg=8)
    stand.cyl((0.9, -1.87, 0.17), (0.9, -1.87, 0.2), 0.135, 0.14, RED, seg=8)

    town = Part("town")
    for x, y, s, pine in ((-5.5, 3.5, 1.5, True), (5.8, 4.2, 1.7, True), (-8.5, 0.5, 1.3, False),
                          (8.6, 1.0, 1.4, False), (-3.4, 7.5, 1.9, True), (3.6, 8.5, 1.6, False),
                          (-11.0, 6.0, 2.0, True), (11.5, 7.0, 2.1, True), (0.5, 11.0, 1.8, True),
                          (-6.5, -3.5, 1.1, False), (7.2, -3.0, 1.2, True)):
        tree(town, x, y, s, pine, rnd)
    # A fence round the back of the green
    last = None
    for k in range(13):
        a = math.radians(20 + k * 11.7)
        p = Vector((math.cos(a) * 4.9, math.sin(a) * 4.9 + 0.3, 0))
        town.cyl(p, p + Vector((0, 0, 0.75)), 0.06, 0.05, BROWN_D, WOOD, seg=5)
        if last:
            for z in (0.3, 0.58):
                town.cyl(last + Vector((0, 0, z)), p + Vector((0, 0, z)), 0.03, 0.03, WOOD, seg=4)
        last = p
    # The town beyond: a clock tower and a few roofs
    town.box((-7.0, 16.0, 4.5), (2.6, 2.6, 9.0), STONE, STONE_D)
    town.cyl((-7.0, 16.0, 9.0), (-7.0, 16.0, 11.6), 2.3, 0.0, RED, RED_D, seg=4)
    for x, y, w, h, c in ((-11.5, 15.0, 3.4, 2.8, WOOD_L), (-2.5, 17.5, 3.8, 3.2, CREAM),
                          (3.5, 17.0, 3.0, 2.6, STONE), (9.0, 15.5, 3.6, 3.0, WOOD_L)):
        town.box((x, y, h / 2), (w, 3.0, h), c, STONE_D)
        town.cyl((x, y, h), (x, y, h + 1.6), w * 0.8, 0.0, RED_D if x > 0 else BLUE_D, DARK, seg=4)
    for k in range(9):
        a = math.tau * k / 9 + 0.3
        town.ball((math.cos(a) * 30, math.sin(a) * 30, 1.0), (9.0, 9.0, rnd.uniform(4.0, 7.0)),
                  GREEN_D, GREEN_DD, seg=6, rings=4)
    # Toadstools and flowers in the grass
    for k in range(16):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(2.6, 5.6)
        x, y = math.cos(a) * r, math.sin(a) * r
        if y < -1.5 and abs(x) < 3.5:
            continue
        if k % 3 == 0:
            town.cyl((x, y, 0), (x, y, 0.16), 0.035, 0.03, CREAM, seg=4)
            town.cyl((x, y, 0.14), (x, y, 0.25), 0.11, 0.0, RED, seg=6)
        else:
            town.cyl((x, y, 0), (x, y, 0.14), 0.012, 0.012, GREEN_D, seg=4)
            town.ball((x, y, 0.16), 0.045, rnd.choice([WHITE, GOLD, PURPLE_L, "#ff8fb0"]), seg=5, rings=3)

    # Trees with nothing left on them
    for x, y, s in ((-4.6, 1.4, 1.5), (5.2, 0.6, 1.3), (-9.5, 4.5, 2.0), (7.6, 9.5, 1.8)):
        town.cyl((x, y, 0), (x + 0.1 * s, y, 1.6 * s), 0.16 * s, 0.09 * s, "#1f150f", "#2e2018", seg=5)
        for k in range(5):
            a = k * 1.9 + x
            base = Vector((x + 0.1 * s, y, (1.0 + k * 0.22) * s))
            tip = base + Vector((math.cos(a) * 0.8, math.sin(a) * 0.5, 0.55 + k * 0.1)) * s
            town.cyl(base, tip, 0.05 * s, 0.01 * s, "#2e2018", seg=4)
            town.cyl(tip, tip + Vector((math.cos(a + 1.0) * 0.35, 0.1, 0.3)) * s, 0.02 * s, 0.0, "#2e2018", seg=4)
    # Pumpkins by the stand
    for x, y, r in ((2.9, -0.7, 0.2), (3.2, -0.35, 0.14), (-3.0, -0.6, 0.17), (-2.6, 1.9, 0.22), (2.7, 1.8, 0.16)):
        town.ball((x, y, r * 0.75), (r, r, r * 0.78), "#e8761c", "#a8440e", seg=7, rings=4)
        town.cyl((x, y, r * 1.45), (x + 0.02, y, r * 1.8), 0.025, 0.015, "#3d4a1c", seg=4)
    # The big top beyond the trees, striped, and the legs the wheel stands on
    for k in range(14):
        a = math.tau * k / 14
        town.box((10.0 + math.cos(a) * 5.0, 23.0 + math.sin(a) * 5.0, 1.7), (2.3, 0.2, 3.4),
                 "#a81f1f" if k % 2 == 0 else "#d8cfae", "#1c1622", rot=(0, 0, a + math.pi / 2))
    town.cyl((10.0, 23.0, 3.3), (10.0, 23.0, 7.6), 5.6, 0.3, "#7a1518", "#a81f1f", seg=14)
    town.cyl((10.0, 23.0, 7.6), (10.0, 23.0, 9.2), 0.06, 0.06, DARK, seg=4)
    town.cyl((10.0, 23.0, 9.2), (10.9, 23.0, 8.95), 0.3, 0.0, "#d8cfae", seg=3)
    for s in (1, -1):
        town.cyl((-13.0 + 3.0 * s, 25.0, 0), (-13.0, 25.0, 7.5), 0.16, 0.12, "#1c1622", seg=5)

    wheel = Part("wheel", None, (-13.0, 24.7, 7.5))
    for k in range(12):
        a = math.tau * k / 12
        b = math.tau * (k + 1) / 12
        p = Vector((-13.0 + math.cos(a) * 5.2, 24.7, 7.5 + math.sin(a) * 5.2))
        q = Vector((-13.0 + math.cos(b) * 5.2, 24.7, 7.5 + math.sin(b) * 5.2))
        wheel.cyl(p, q, 0.09, 0.09, "#1c1622", seg=4)
        if k % 2 == 0:
            wheel.cyl((-13.0, 24.7, 7.5), p, 0.06, 0.06, "#1c1622", seg=4)
        wheel.box(p + Vector((0, 0, -0.45)), (0.7, 0.5, 0.6), "#7a1518" if k % 2 == 0 else "#3b2a4a", "#1c1622")
    wheel.cyl((-13.0, 24.5, 7.5), (-13.0, 24.9, 7.5), 0.4, 0.4, "#1c1622", seg=8)

    # Whatever shines by its own light
    glow = Part("glow_lamps")
    for s in (1, -1):
        glow.ball((2.4 * s, 1.7, 3.8), 0.17, LAMP, seg=6, rings=4)
        glow.cyl((1.25 * s, 1.62, 3.15), (1.25 * s, 1.62, 2.95), 0.005, 0.005, LAMP, seg=4)
        glow.ball((1.25 * s, 1.62, 2.85), 0.13, LAMP, seg=6, rings=4)
    glow.cyl((-7.0, 14.68, 7.2), (-7.0, 14.7, 7.2), 0.85, 0.85, "#fff3c4", seg=10)
    # A string of bulbs sagging between the posts and away to either side, not all of them working
    for k in range(25):
        t = k / 24.0
        x = -6.0 + t * 12.0
        sag = 0.5 * math.sin(math.pi * ((x + 6.0) % 3.6) / 3.6)
        if k % 7 != 3:
            glow.ball((x, 1.66, 3.55 - sag), 0.07, ["#ffd76a", "#ff7a4a", "#fff3c4"][k % 3], seg=4, rings=3)
    clock = Part("clock_hands")
    clock.box((-7.0, 14.66, 7.5), (0.1, 0.03, 0.62), DARK)
    clock.box((-6.82, 14.66, 7.2), (0.42, 0.03, 0.1), DARK)

    write("stage")


# The little folk on the green, who have come out of the woods for the music: three satyr
# kids (goat legs, hooves, horns) and three straw-hatted wood imps (a dark wooden face with
# lit eyes, a ragged poncho, stick limbs). Each has limbs of its own to run with. They are
# still named kid0 to kid5, with kidN_leg_L and so on, which is what the game looks for.
def build_kids():
    fresh()
    fur = ["#7a4a22", "#5a3a20", "#9a6a3a"]
    hide = ["#e0b088", "#c98f62", "#f0c9a0"]
    cloth = ["#d9572a", "#3f8f4a", "#b03a5a"]
    wood = "#3a2a1c"
    straw = "#dcb85e"
    for i in range(6):
        size = 0.85 + (i % 3) * 0.1
        k = i // 2
        kid = Part("kid%d" % i)
        if i % 2 == 0:
            # A satyr
            kid.ball((0, 0.01, 0.36), (0.13, 0.12, 0.11), fur[k], seg=6, rings=4)
            kid.cyl((0, 0, 0.38), (0, 0, 0.62), 0.1, 0.105, hide[k], seg=6, flat=0.8)
            kid.ball((0, 0, 0.62), (0.105, 0.085, 0.04), hide[k], seg=6, rings=3)
            kid.cyl((0, 0.11, 0.4), (0, 0.19, 0.47), 0.03, 0.0, fur[k], seg=4)
            kid.ball((0, 0, 0.8), (0.15, 0.145, 0.15), hide[k], seg=8, rings=5)
            kid.ball((0, 0.03, 0.85), (0.16, 0.16, 0.12), fur[k], seg=8, rings=4)
            kid.cyl((0, -0.13, 0.69), (0, -0.15, 0.6), 0.03, 0.0, fur[k], seg=4)
            for s_ in (1, -1):
                kid.ball((0.055 * s_, -0.135, 0.8), 0.02, DARK, seg=4, rings=3)
                kid.cyl((0.14 * s_, 0.0, 0.8), (0.27 * s_, 0.03, 0.86), 0.035, 0.0, hide[k], seg=4)
                kid.cyl((0.07 * s_, 0.0, 0.92), (0.11 * s_, 0.04, 1.02), 0.03, 0.02, CREAM, seg=5)
                kid.cyl((0.11 * s_, 0.04, 1.02), (0.1 * s_, 0.1, 1.08), 0.02, 0.0, CREAM, seg=5)
            kid.ball((0, -0.143, 0.745), (0.04, 0.012, 0.012), "#8a2a22", seg=4, rings=3)
        else:
            # A wood imp
            kid.cyl((0, 0, 0.26), (0, 0, 0.66), 0.2, 0.07, cloth[k], seg=7)
            for a in range(7):
                ang = math.tau * a / 7
                kid.cyl((math.cos(ang) * 0.17, math.sin(ang) * 0.17, 0.27), (math.cos(ang) * 0.2, math.sin(ang) * 0.2, 0.17),
                        0.045, 0.0, cloth[k], seg=4)
            kid.cyl((0, 0, 0.6), (0, 0, 0.68), 0.1, 0.075, cloth[(k + 1) % 3], seg=6)
            kid.ball((0, 0, 0.8), (0.14, 0.14, 0.145), wood, seg=8, rings=5)
            for s_ in (1, -1):
                kid.ball((0.055 * s_, -0.125, 0.81), (0.034, 0.02, 0.04), "#ffb52e", seg=5, rings=3)
            kid.cyl((0, -0.13, 0.76), (0, -0.2, 0.74), 0.03, 0.0, "#e8c890", seg=4)
            kid.cyl((0, 0, 0.9), (0, 0, 0.93), 0.3, 0.27, straw, seg=8)
            kid.cyl((0, 0, 0.93), (0, 0, 1.12), 0.17, 0.02, straw, "#b8923c", seg=8)
            kid.cyl((0, 0, 0.93), (0, 0, 0.965), 0.172, 0.16, cloth[(k + 1) % 3], seg=8)
        for s_, side in ((1, "L"), (-1, "R")):
            leg = Part("kid%d_leg_%s" % (i, side), kid, (0.055 * s_, 0, 0.32))
            arm = Part("kid%d_arm_%s" % (i, side), kid, (0.13 * s_, 0, 0.58))
            if i % 2 == 0:
                leg.cyl((0.055 * s_, 0.02, 0.17), (0.055 * s_, 0, 0.32), 0.045, 0.07, fur[k], seg=5)
                leg.cyl((0.055 * s_, -0.01, 0.05), (0.055 * s_, 0.02, 0.17), 0.028, 0.04, fur[k], seg=5)
                leg.cyl((0.055 * s_, -0.02, 0.0), (0.055 * s_, -0.01, 0.06), 0.045, 0.035, DARK, seg=5)
                arm.cyl((0.15 * s_, 0, 0.36), (0.13 * s_, 0, 0.58), 0.032, 0.04, hide[k], seg=5)
                arm.ball((0.15 * s_, 0, 0.35), 0.04, hide[k], seg=5, rings=3)
            else:
                leg.cyl((0.055 * s_, 0, 0.05), (0.055 * s_, 0, 0.32), 0.022, 0.026, wood, seg=4)
                leg.cyl((0.055 * s_, 0.03, 0.03), (0.055 * s_, -0.13, 0.05), 0.04, 0.0, cloth[(k + 1) % 3], seg=5)
                arm.cyl((0.145 * s_, 0, 0.46), (0.13 * s_, 0, 0.58), 0.05, 0.035, cloth[k], seg=5)
                arm.cyl((0.16 * s_, 0, 0.33), (0.145 * s_, 0, 0.46), 0.02, 0.022, wood, seg=4)
                arm.ball((0.16 * s_, 0, 0.32), 0.03, wood, seg=5, rings=3)
        for part in PARTS[-5:]:
            part.resize(size)
            part.pivot = part.pivot * size
    write("kids")


build_bandsman()
build_stage()
build_kids()
