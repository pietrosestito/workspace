"""Blender script: pre-renders the fighters from 3D bodies (Donkey Kong Country style).

Bodies are built with Blender's own Skin modifier: a graph of joints, each with a
muscle radius, turned into a smooth organic mesh (Subdivision Surface). Every pose
re-places the joints with forward kinematics from the same angles used by
mkfighters.py, then Cycles renders the frame (orthographic, side view turned 3/4).

Units: 1 Blender unit = 1 pixel of the final 176x176 frame; feet at z = 0.

usage: blender -b --factory-startup -P tools/render3d.py -- POSES.json OUTDIR [char ...] [--only pose,pose]
writes OUTDIR/<char>/<pose>.png (4x size, RGBA) and OUTDIR/<char>/tips.json
"""
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index('--') + 1:]
POSES_JSON, OUTDIR = argv[0], argv[1]
rest = argv[2:]
ONLY = None
if '--only' in rest:
    i = rest.index('--only')
    ONLY = rest[i + 1].split(',')
    rest = rest[:i] + rest[i + 2:]
CHARS = rest or ['nonno', 'toro']

FS, OX, OY = 176, 88, 172
SCALE = 4                      # render at 4x, reduced later with a box filter
YAW = -50                      # body turned towards the camera (3/4 view)


def srgb(c):
    """0-255 sRGB -> linear RGBA for Blender materials."""
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1)


# --------------------------------------------------------------------------- characters
CHAR = {
    'nonno': dict(thigh=28, shin=27, uarm=22, farm=20, torso=40, neck=5, shoulders=40, hipw=15,
                  r=dict(pelvis=(9, 12), abdomen=(8.5, 11), chest=(10, 15), upper=(9, 15), neck=5.5, delt=7.8, bicep=6.4,
                         elbow=4.2, fore=5.6, wrist=3.4, fist=4.6, hip=9.5, thigh=9.8, knee=5.8, calf=6.6, ankle=3.6, toe=3,
                         pec=7.5, lat=7.5),
                  skin=(232, 186, 150), top=(60, 110, 215), shorts=(50, 56, 98), feet=None, head='nonno'),
    'toro': dict(thigh=30, shin=28, uarm=24, farm=22, torso=46, neck=4, shoulders=54, hipw=19,
                 r=dict(pelvis=(11.5, 15), abdomen=(11, 14), chest=(14, 20), upper=(12.5, 21), neck=10, delt=11, bicep=9.4,
                        elbow=5.6, fore=7.6, wrist=4.6, fist=6, hip=12, thigh=12.8, knee=7.2, calf=8.8, ankle=4.6, toe=3.8,
                        pec=10.5, lat=10.5),
                 skin=(126, 74, 42), top=None, shorts=(205, 36, 36), feet=(52, 34, 26), head='toro'),
}


# --------------------------------------------------------------------------- scene
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.render.resolution_x = sc.render.resolution_y = FS * SCALE
    sc.render.film_transparent = True
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'Medium High Contrast'
    world = bpy.data.worlds.new('w')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (0.35, 0.33, 0.45, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = 0.25
    sc.world = world
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    cam.ortho_scale = FS
    co = bpy.data.objects.new('cam', cam)
    co.location = (0, -500, OY - FS / 2)
    co.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(co)
    sc.camera = co
    for name, d, e in (('key', (0.8, 0.45, -0.6), 4.5), ('fill', (-0.9, 0.3, -0.2), 0.6), ('rim', (-0.6, 0.8, 0.2), 4.0)):
        l = bpy.data.lights.new(name, 'SUN')
        l.energy = e
        l.angle = math.radians(8)
        lo = bpy.data.objects.new(name, l)
        lo.rotation_euler = Vector(d).to_track_quat('-Z', 'Y').to_euler()
        sc.collection.objects.link(lo)
    return sc


def material(name, rgb, rough=0.55, sss=0.0, metal=0.0, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = srgb(rgb)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if sss:
        b.inputs['Subsurface Weight'].default_value = sss
        b.inputs['Subsurface Radius'].default_value = (1.0, 0.4, 0.25)
        b.inputs['Subsurface Scale'].default_value = 1.5
    if sheen:
        b.inputs['Sheen Weight'].default_value = sheen
    return m


class SkinBody:
    """A Skin-modifier mesh whose joints are moved for every pose."""

    def __init__(self, name, names, edges, radii, mat, root, levels=2):
        self.names = names
        me = bpy.data.meshes.new(name)
        me.from_pydata([(0, 0, i * 0.01) for i in range(len(names))], edges, [])
        self.obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(self.obj)
        sk = self.obj.modifiers.new('skin', 'SKIN')
        sk.use_smooth_shade = True
        sk.branch_smoothing = 0.5
        sub = self.obj.modifiers.new('sub', 'SUBSURF')
        sub.levels = sub.render_levels = levels
        data = me.skin_vertices[0].data
        for i, n in enumerate(names):
            r = radii[n]
            data[i].radius = (r, r) if not isinstance(r, tuple) else r
            data[i].use_root = (n == root)
        me.materials.append(mat)

    def place(self, pos):
        me = self.obj.data
        for i, n in enumerate(self.names):
            me.vertices[i].co = pos[n]
        me.update()


# --------------------------------------------------------------------------- skeleton
BODY_EDGES = [('pelvis', 'abdomen'), ('abdomen', 'chest'), ('chest', 'upper'), ('upper', 'neck'),
              ('chest', 'b_pec'), ('chest', 'f_pec'), ('chest', 'b_lat'), ('chest', 'f_lat'),
              ('upper', 'b_sh'), ('b_sh', 'b_bicep'), ('b_bicep', 'b_elbow'), ('b_elbow', 'b_fore'), ('b_fore', 'b_wrist'), ('b_wrist', 'b_fist'),
              ('upper', 'f_sh'), ('f_sh', 'f_bicep'), ('f_bicep', 'f_elbow'), ('f_elbow', 'f_fore'), ('f_fore', 'f_wrist'), ('f_wrist', 'f_fist'),
              ('pelvis', 'b_hip'), ('b_hip', 'b_thigh'), ('b_thigh', 'b_knee'), ('b_knee', 'b_calf'), ('b_calf', 'b_ankle'), ('b_ankle', 'b_toe'),
              ('pelvis', 'f_hip'), ('f_hip', 'f_thigh'), ('f_thigh', 'f_knee'), ('f_knee', 'f_calf'), ('f_calf', 'f_ankle'), ('f_ankle', 'f_toe')]
RADKEY = {'pelvis': 'pelvis', 'abdomen': 'abdomen', 'chest': 'chest', 'upper': 'upper', 'neck': 'neck',
          'sh': 'delt', 'bicep': 'bicep', 'elbow': 'elbow', 'fore': 'fore', 'wrist': 'wrist', 'fist': 'fist',
          'hip': 'hip', 'thigh': 'thigh', 'knee': 'knee', 'calf': 'calf', 'ankle': 'ankle', 'toe': 'toe',
          'pec': 'pec', 'lat': 'lat'}


def joint_names():
    names = []
    for a, b in BODY_EDGES:
        for n in (a, b):
            if n not in names:
                names.append(n)
    return names


def radius_of(c, n):
    return c['r'][RADKEY[n.split('_', 1)[-1]]]


def d2(a):
    """2D pose angle (0 down, 90 forward) -> (x, z) unit vector."""
    r = math.radians(a)
    return math.sin(r), -math.cos(r)


def fk(c, pose):
    """Joint positions (before yaw) for one pose. x forward, y depth (+ away from camera), z up."""
    k = (c['thigh'] + c['shin']) / 26
    hx = pose['hip'][0] * k
    hz = c['thigh'] + c['shin'] + 3 - pose['hip'][1] * k
    lean = math.radians(pose['lean'])
    up = (math.sin(lean), math.cos(lean))
    T = c['torso']
    P = {}

    def spine(t):
        return Vector((hx + up[0] * T * t, 0, hz + up[1] * T * t))
    P['pelvis'], P['abdomen'], P['chest'], P['upper'] = spine(0), spine(0.33), spine(0.62), spine(0.86)
    P['neck'] = spine(1.0) + Vector((up[0], 0, up[1])) * c['neck']
    fwd = Vector((math.cos(lean), 0, -math.sin(lean)))
    upv = Vector((up[0], 0, up[1]))
    wid = c['shoulders'] / 2
    for side, sgn in (('b', 1), ('f', -1)):
        P[side + '_pec'] = spine(0.7) + fwd * 4 + Vector((0, sgn * wid * 0.42, 0))
        P[side + '_lat'] = spine(0.5) - fwd * 2 + Vector((0, sgn * wid * 0.6, 0))
        sh = spine(0.86) + Vector((0, sgn * c['shoulders'] / 2, 0)) - Vector((up[0], 0, up[1])) * 1.5
        P[side + '_sh'] = sh
        a1, a2 = pose[side + 'arm'][0], pose[side + 'arm'][0] + pose[side + 'arm'][1]
        u, f = d2(a1), d2(a2)
        el = sh + Vector((u[0], 0, u[1])) * c['uarm']
        wr = el + Vector((f[0], 0, f[1])) * c['farm']
        P[side + '_bicep'] = sh.lerp(el, 0.5)
        P[side + '_elbow'] = el
        P[side + '_fore'] = el.lerp(wr, 0.3)
        P[side + '_wrist'] = wr
        P[side + '_fist'] = wr + Vector((f[0], 0, f[1])) * c['r']['fist'] * 0.9
        hip = spine(0) + Vector((0, sgn * c['hipw'] / 2, 0)) - Vector((up[0], 0, up[1])) * 3
        P[side + '_hip'] = hip
        l1, l2 = pose[side + 'leg'][0], pose[side + 'leg'][0] + pose[side + 'leg'][1]
        t_, s_ = d2(l1), d2(l2)
        kn = hip + Vector((t_[0], 0, t_[1])) * c['thigh']
        an = kn + Vector((s_[0], 0, s_[1])) * c['shin']
        P[side + '_thigh'] = hip.lerp(kn, 0.45)
        P[side + '_knee'] = kn
        P[side + '_calf'] = kn.lerp(an, 0.3)
        P[side + '_ankle'] = an
        ft = d2(l2 + 90)
        P[side + '_toe'] = an + Vector((ft[0], 0, ft[1])) * 8
    return P, up


def yawed(p):
    return Euler((0, 0, math.radians(YAW))).to_matrix() @ p


# --------------------------------------------------------------------------- heads
def ellipsoid(name, loc, size, mat, rot=(0, 0, 0), parent=None, seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1)
    o = bpy.context.active_object
    o.name = name
    o.location, o.scale, o.rotation_euler = loc, size, rot
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if parent:
        o.parent = parent
    return o


def build_head(kind, c):
    """Head built around an empty at the base of the skull, face looking +x."""
    root = bpy.data.objects.new('head_' + kind, None)
    bpy.context.scene.collection.objects.link(root)
    dark = material('dark', (30, 20, 20), 0.4)
    white = material('white', (245, 242, 235), 0.3)
    tips = {}
    if kind == 'nonno':
        skin = material('hskin', c['skin'], 0.5, sss=0.15)
        hair = material('hair', (205, 205, 212), 0.7, sheen=0.4)
        stub = material('stubble', (176, 160, 150), 0.8)
        ellipsoid('skull', (0, 0, 15), (11, 10, 13), skin, parent=root)
        ellipsoid('jaw', (2.5, 0, 8.5), (9, 8.5, 7.5), stub, parent=root)
        ellipsoid('face', (4, 0, 12), (8.5, 8, 9), skin, parent=root)
        ellipsoid('nose', (11.2, 0, 13.2), (2.4, 1.8, 3.2), skin, rot=(0, math.radians(-15), 0), parent=root)
        for s in (1, -1):
            ellipsoid('ear', (-1.5, s * 10, 13.5), (2.6, 1.2, 3.6), skin, parent=root)
            ellipsoid('eye', (9.6, s * 3.6, 15.2), (1.2, 1.7, 1.0), white, parent=root)
            ellipsoid('iris', (10.6, s * 3.4, 15.2), (0.6, 0.9, 0.9), dark, parent=root)
            ellipsoid('brow', (9.6, s * 3.8, 17.6), (1.3, 2.6, 0.8), hair, parent=root)
            ellipsoid('sidehair', (-3.5, s * 8.5, 17), (6.5, 3.2, 6.5), hair, parent=root)
        ellipsoid('backhair', (-6.5, 0, 16), (5.5, 9.5, 8), hair, parent=root)
        ellipsoid('fringe', (1, 0, 26.3), (7, 6, 1.6), hair, parent=root)
        ellipsoid('mouth', (10.0, 0, 8.6), (1.4, 4.4, 1.4), dark, parent=root)
        ellipsoid('teeth', (10.6, 0, 9.3), (1.0, 3.4, 0.7), white, parent=root)
        tips['head'] = Vector((12, 0, 16))
    else:
        fur = material('fur', c['skin'], 0.75, sheen=0.5)
        fur2 = material('fur2', (88, 50, 28), 0.8, sheen=0.5)
        snout = material('snout', (214, 160, 132), 0.45, sss=0.1)
        horn = material('horn', (238, 228, 196), 0.35)
        gold = material('gold', (255, 200, 60), 0.25, metal=1.0)
        red = material('red', (200, 20, 20), 0.3)
        ellipsoid('skull', (0, 0, 16), (12, 11.5, 12), fur, parent=root)
        ellipsoid('tuft', (1, 0, 27), (5, 5, 3), fur2, parent=root)
        ellipsoid('snout', (11, 0, 8.5), (8.5, 8, 6.5), snout, rot=(0, math.radians(-12), 0), parent=root)
        for s in (1, -1):
            ellipsoid('nostril', (18.5, s * 3, 9.5), (0.9, 1.4, 1.2), dark, parent=root)
            ellipsoid('eye', (8.5, s * 6.8, 18), (1.6, 1.2, 1.4), white, parent=root)
            ellipsoid('pupil', (9.6, s * 6.9, 18), (0.8, 0.8, 1.0), red, parent=root)
            ellipsoid('brow', (8.5, s * 6.5, 20.2), (2.2, 2.6, 0.9), fur2, rot=(math.radians(s * 20), 0, 0), parent=root)
            ellipsoid('ear', (-2, s * 13, 19), (3.5, 1.5, 2.2), fur2, rot=(math.radians(s * 25), 0, 0), parent=root)
            # horn: a tapering chain of spheres curving out and up
            for i in range(9):
                t = i / 8
                ang = math.radians(10 + 70 * t)
                pos = (2 - 2 * t, s * (10 + 9 * math.cos(ang) * t * 1.2), 23 + 10 * t * math.sin(ang) + 3 * t)
                r = 3.0 * (1 - t) + 0.7
                ellipsoid('horn', pos, (r, r, r), horn, parent=root, seg=12)
        bpy.ops.mesh.primitive_torus_add(major_radius=3.2, minor_radius=0.7, location=(19, 0, 6),
                                         rotation=(0, math.radians(90), 0))
        ring = bpy.context.active_object
        ring.data.materials.append(gold)
        ring.parent = root
        tips['head'] = Vector((20, 0, 14))
    return root, tips


# --------------------------------------------------------------------------- render
def render_char(name, poses, outdir):
    c = CHAR[name]
    sc = reset_scene()
    names = joint_names()
    skin = material('skin', c['skin'], 0.5 if name == 'nonno' else 0.7, sss=0.15 if name == 'nonno' else 0.0,
                    sheen=0.0 if name == 'nonno' else 0.5)
    radii = {n: radius_of(c, n) for n in names}
    body = SkinBody('body', names, [(names.index(a), names.index(b)) for a, b in BODY_EDGES], radii, skin, 'pelvis')
    if c['feet']:                                                  # hooves: darker feet
        hoof = material('hoof', c['feet'], 0.4)
        hoofs = []
        for side in ('b', 'f'):
            hn = [side + '_ankle', side + '_toe']
            hoofs.append(SkinBody('hoof', hn, [(0, 1)], {hn[0]: c['r']['ankle'] + 0.6, hn[1]: c['r']['toe'] + 0.8}, hoof, hn[0]))
    else:
        hoofs = []
    # clothes: slightly bigger skins over the same joints
    sh_names = ['b_thigh', 'b_hip', 'pelvis', 'f_hip', 'f_thigh']
    pr = c['r']['pelvis']
    sh_r = {'pelvis': (pr[0] + 1.5, pr[1] + 1.5), 'b_hip': c['r']['hip'] + 1.6, 'f_hip': c['r']['hip'] + 1.6,
            'b_thigh': c['r']['thigh'] + 1.0, 'f_thigh': c['r']['thigh'] + 1.0}
    shorts = SkinBody('shorts', sh_names, [(0, 1), (1, 2), (2, 3), (3, 4)], sh_r, material('shorts', c['shorts'], 0.8), 'pelvis', levels=3)
    shorts.obj.modifiers['skin'].branch_smoothing = 1.0
    top = None
    if c['top']:
        tn = ['pelvis', 'abdomen', 'chest', 'upper']
        grow = lambda r, g: (r[0] + g, r[1] + g)
        tr = {'pelvis': grow(c['r']['pelvis'], 0.8), 'abdomen': grow(c['r']['abdomen'], 1.0), 'chest': grow(c['r']['chest'], 1.4),
              'upper': (c['r']['upper'][0] + 0.6, c['r']['upper'][1] - 3)}
        top = SkinBody('top', tn, [(0, 1), (1, 2), (2, 3)], tr, material('top', c['top'], 0.75), 'pelvis')
    belt = None
    for o in [body, shorts, top] + hoofs:
        if o:
            o.obj.rotation_euler = (0, 0, math.radians(YAW))
    head, htips = build_head(c['head'], c)
    os.makedirs(outdir, exist_ok=True)
    tips_out = {}
    for pname, pose in poses.items():
        P, up = fk(c, pose)
        W = P                                            # objects carry the yaw
        body.place(W)
        for h in hoofs:
            h.place(W)
        shorts.place(W)
        if top:
            top.place(W)
        if belt:
            pass
        neck = P['neck']
        head.location = yawed(neck + Vector((pose['head'][0], 0, -pose['head'][1])))
        head.rotation_euler = Euler((0, math.radians(pose['lean']), math.radians(YAW)), 'XYZ')
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(outdir, pname + '.png')
        bpy.ops.render.render(write_still=True)
        # hit point of the pose, projected into the final frame
        hit = pose.get('hit')
        tip = None
        if hit:
            if hit == 'head':
                w = head.matrix_world @ htips['head']
            else:
                key = {'farm': 'f_fist', 'barm': 'b_fist', 'fleg': 'f_toe', 'bleg': 'b_toe'}[hit]
                w = yawed(W[key])
            v = world_to_camera_view(sc, sc.camera, w)
            tip = (round(v.x * FS) - OX, round((1 - v.y) * FS) - OY)
        tips_out[pname] = tip
        print('rendered', name, pname, flush=True)
    with open(os.path.join(outdir, 'tips.json'), 'w') as f:
        json.dump(tips_out, f)


if __name__ == '__main__':
    with open(POSES_JSON) as f:
        allp = json.load(f)
    for ch in CHARS:
        poses = allp[ch]
        if ONLY:
            poses = {k: v for k, v in poses.items() if k in ONLY}
        render_char(ch, poses, os.path.join(OUTDIR, ch))
