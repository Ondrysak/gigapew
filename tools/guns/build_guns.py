"""Original metre-scale gun assets. Run: blender -b --python tools/guns/build_guns.py
Rebuild one weapon: blender -b --python tools/guns/build_guns.py -- --weapon pulse
(ids: pulse rail scatter minigun autocannon flamethrower; repeat --weapon for several)
Godot axes in authoring helpers: X right, Y up, -Z muzzle. No external assets.
Every gun is improvised junk held by the same grimy fingerless-gloved hand.
"""
import bpy
import math
import argparse
import os
import sys
from mathutils import Matrix, Vector

OUT = os.path.abspath('assets/guns')
os.makedirs(OUT, exist_ok=True)

def xyz(p):
    return (p[0], -p[2], p[1])

def material(name, color, metal=0, rough=.55, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

# Lahve od piva: a grimy fingerless-gloved hand and a generic brown 0.5 l bottle.
# Faint amber self-light keeps the brown glass from reading olive under the
# arenas' blue ambient light, in the hand and in flight.
GLASS = material('Brown bottle glass', (.2,.075,.014), 0,.3,.35)
LABEL = material('Paper label', (.72,.6,.38), 0,.82)
PRINT = material('Label print', (.5,.05,.035), 0,.6)
FOIL = material('Neck foil', (.62,.43,.12), .7,.35)
CAP = material('Crown cap', (.6,.55,.42), .85,.33)
SKIN = material('Grimy skin', (.5,.25,.14), 0,.74)
NAIL = material('Dirty nail', (.16,.12,.07), 0,.6)
WOOL = material('Fingerless wool glove', (.11,.042,.032), 0,.97)
JACKET = material('Worn jacket', (.05,.058,.03), 0,.9)
# Junk shared by the other five guns: rust, tape, pipe, cardboard, vinyl.
# Dull finishes with a faint warm self-light, so tobacco, rust and bone stay
# readable instead of picking up the arenas' blue ambient.
RUST = material('Rusty rebar', (.2,.05,.018), .1,.72,.5)
RUSTDARK = material('Scaled rust', (.08,.022,.01), .1,.8,.5)
IRON = material('Galvanized pipe', (.12,.105,.08), 0,.8,.5)
DARKIRON = material('Old black iron', (.03,.025,.02), .1,.7,.5)
GAFFER = material('Gaffer tape', (.014,.012,.011), 0,.9,.5)
DUCT = material('Duct tape', (.12,.095,.055), 0,.85,.5)
WOOD = material('Veneer', (.12,.035,.014), 0,.7,.5)
BOARD = material('Cardboard', (.2,.105,.04), 0,.92,.45)
BONE = material('Dirty bone plastic', (.27,.22,.12), 0,.85,.4)
SIGNRED = material('Sign paint', (.2,.016,.011), 0,.6,.5)
BRISTLE = material('Toilet brush', (.05,.034,.022), 0,.95,.4)
VINYL = material('Vinyl', (.006,.006,.007), .1,.35,.5)
GROOVE = material('Vinyl groove sheen', (.022,.022,.026), .2,.3,.5)
VLABEL = material('Record label', (.42,.07,.012), 0,.7,.6)
PIGEON = material('Pigeon grey', (.15,.15,.16), 0,.88,.4)
PIGEONDARK = material('Pigeon wing', (.075,.078,.088), 0,.88,.4)
SHEEN = material('Pigeon neck sheen', (.07,.13,.11), 0,.6,.4)
BEAK = material('Pigeon beak', (.45,.2,.04), 0,.6,.5)
EYE = material('Pigeon eye', (.8,.32,.05), 0,.5,.8)
BREAD = material('Bread roll', (.32,.12,.022), 0,.9,.5)
BREADCUT = material('Bread crumb', (.5,.3,.1), 0,.9,.5)
TIN = material('Tin can', (.17,.14,.1), .1,.55,.5)
RUBBERTYRE = material('Bike tyre', (.012,.011,.01), 0,.85,.3)
ABSINTH = material('Absinth glass', (.012,.085,.022), 0,.3,.55)
RAG = material('Oily rag', (.3,.26,.17), 0,.95,.4)
FLAMEOUT = material('Flame', (1,.3,.03), 0,.5,1.0)
FLAMEIN = material('Flame core', (1,.55,.1), 0,.5,1.3)
RUMGLASS = material('Rum glass', (.11,.028,.007), 0,.3,.5)
SPRAY = material('Hairspray can', (.22,.2,.16), .1,.5,.4)
SPRAYCAP = material('Hairspray cap', (.22,.025,.018), 0,.6,.5)
LIGHTER = material('Lighter body', (.32,.035,.022), 0,.4,.5)
SHIFT = (-.03,.075,-.1)
ROOT = None

def finish(o, name, mat, parent=None, bevel=0):
    o.name = name
    o.data.materials.append(mat)
    o.parent = parent or ROOT
    if bevel:
        mod = o.modifiers.new('Machined edge radius', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod = o.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def _mesh(name, verts, faces, mat, parent=None, smooth=False, closed=False):
    # Godot-space vertices. `closed` solids are flipped outward when needed.
    if closed:
        volume = 0
        for f in faces:
            for k in range(1, len(f) - 1):
                a, b, c = (Vector(verts[f[0]]), Vector(verts[f[k]]), Vector(verts[f[k + 1]]))
                volume += a.dot(b.cross(c))
        if volume < 0:
            faces = [tuple(reversed(f)) for f in faces]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([xyz(v) for v in verts], [], faces)
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return finish(o, name, mat, parent)

def rotation(rx=0, ry=0, rz=0):
    # Godot-axis euler degrees, applied X then Y then Z.
    return Matrix.Rotation(math.radians(rz), 3, 'Z') @ Matrix.Rotation(math.radians(ry), 3, 'Y') @ Matrix.Rotation(math.radians(rx), 3, 'X')

CUBE_FACES = [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)]
def slab(name, c, size, mat, rot=(0,0,0), parent=None, taper=1.0):
    # Hard-edged plank centred on c; `taper` scales the far (-Z) end's X/Y.
    r = rotation(*rot); c = Vector(c); hx, hy, hz = (s / 2 for s in size)
    verts = []
    corners = [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
    for sx, sy, sz in corners:
        k = taper if sz < 0 else 1.0
        verts.append(c + r @ Vector((sx * hx * k, sy * hy * k, sz * hz)))
    return _mesh(name, verts, CUBE_FACES, mat, parent)

def frame(w):
    w = Vector(w).normalized()
    ref = Vector((0,1,0)) if abs(w.y) < .9 else Vector((1,0,0))
    u = (ref - w * ref.dot(w)).normalized()
    return u, w.cross(u), w

def rod(name, a, b, r0, r1, mat, n=8, parent=None, caps=(True, True), smooth=False):
    # Frustum from a to b with flat caps.
    a = Vector(a); b = Vector(b); u, v, w = frame(b - a)
    verts = []
    for p, r in ((a, r0), (b, max(r1, .0004))):
        for i in range(n):
            t = math.tau * i / n
            verts.append(p + (u * math.cos(t) + v * math.sin(t)) * r)
    ca = len(verts); verts += [a, b]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    if caps[0]: faces += [(ca, (i + 1) % n, i) for i in range(n)]
    if caps[1]: faces += [(ca + 1, n + i, n + (i + 1) % n) for i in range(n)]
    return _mesh(name, verts, faces, mat, parent, smooth)

def pipe(name, a, b, r, inner, mat, n=10, parent=None):
    # Open tube with real bore and wall thickness.
    a = Vector(a); b = Vector(b); u, v, w = frame(b - a)
    verts = []
    for p, rr in ((a, r), (b, r), (a, inner), (b, inner)):
        for i in range(n):
            t = math.tau * i / n
            verts.append(p + (u * math.cos(t) + v * math.sin(t)) * rr)
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + j, n + i), (2 * n + i, 3 * n + i, 3 * n + j, 2 * n + j),
                  (n + i, n + j, 3 * n + j, 3 * n + i), (i, 2 * n + i, 2 * n + j, j)]
    return _mesh(name, verts, faces, mat, parent)

def disc(name, c, normal, r, thick, mat, n=18, parent=None):
    w = Vector(normal).normalized(); c = Vector(c)
    return rod(name, c - w * thick / 2, c + w * thick / 2, r, r, mat, n, parent)

def ring_pipe(name, c, normal, r, inner, thick, mat, n=18, parent=None):
    w = Vector(normal).normalized(); c = Vector(c)
    return pipe(name, c - w * thick / 2, c + w * thick / 2, r, inner, mat, n, parent)

def blob(name, c, radii, mat, rot=(0,0,0), segments=8, rings=5, parent=None):
    # Low-poly ellipsoid; the long axis is local Z.
    r = rotation(*rot); c = Vector(c)
    verts = [c + r @ Vector((0, 0, -radii[2]))]
    for k in range(1, rings):
        phi = math.pi * k / rings; ring = math.sin(phi); z = -math.cos(phi)
        for i in range(segments):
            t = math.tau * i / segments
            verts.append(c + r @ Vector((math.cos(t) * radii[0] * ring, math.sin(t) * radii[1] * ring, z * radii[2])))
    verts.append(c + r @ Vector((0, 0, radii[2])))
    faces = [(0, 1 + (i + 1) % segments, 1 + i) for i in range(segments)]
    for k in range(rings - 2):
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((1 + k * segments + i, 1 + k * segments + j, 1 + (k + 1) * segments + j, 1 + (k + 1) * segments + i))
    last = len(verts) - 1
    faces += [(last, 1 + (rings - 2) * segments + i, 1 + (rings - 2) * segments + (i + 1) % segments) for i in range(segments)]
    return _mesh(name, verts, faces, mat, parent, closed=True)

def torus(name, c, axis, big, small, mat, segments=18, n=6, parent=None):
    u, v, w = frame(axis); c = Vector(c)
    verts = []
    for k in range(segments):
        phi = math.tau * k / segments; e = u * math.cos(phi) + v * math.sin(phi)
        for i in range(n):
            t = math.tau * i / n
            verts.append(c + e * big + (e * math.cos(t) + w * math.sin(t)) * small)
    faces = [(k * n + i, k * n + (i + 1) % n, ((k + 1) % segments) * n + (i + 1) % n, ((k + 1) % segments) * n + i)
             for k in range(segments) for i in range(n)]
    return _mesh(name, verts, faces, mat, parent, closed=True)

def revolve(name, prof, mat, parent=None, n=16, origin=(0,0,0), axis=(0,1,0), side=(1,0,0), arc=None, ripple=None, smooth=True):
    # Surface of revolution in Godot space: prof is (radius, height) pairs along
    # `axis`; radius 0 closes the end with a pole. `arc` limits it to a strip.
    o=Vector(origin); w=Vector(axis).normalized(); u=Vector(side)
    u=(u-w*u.dot(w)).normalized(); v=u.cross(w)
    a0,a1 = arc if arc else (0,math.tau)
    cols = n if arc is None else n+1
    verts=[]; rings=[]
    for r,h in prof:
        if r == 0:
            rings.append([len(verts)]); verts.append(xyz(o+w*h)); continue
        ring=[]
        for i in range(cols):
            a=a0+(a1-a0)*i/n; rr=r*(ripple(i) if ripple else 1)
            ring.append(len(verts)); verts.append(xyz(o+w*h+(u*math.cos(a)+v*math.sin(a))*rr))
        rings.append(ring)
    faces=[]
    for lo,hi in zip(rings,rings[1:]):
        for i in range(n):
            j=(i+1)%cols
            if len(lo)==1: faces.append((lo[0],hi[i],hi[j]))
            elif len(hi)==1: faces.append((lo[i],hi[0],lo[j]))
            else: faces.append((lo[i],hi[i],hi[j],lo[j]))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    ob=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(ob)
    finish(ob,name,mat,parent)
    for poly in mesh.polygons: poly.use_smooth=smooth
    return ob

def limb(name, a, b, r0, r1, mat, parent=None, n=10):
    # Rounded sausage from a to b: fingers, thumb, wrist and sleeve.
    a=Vector(a); b=Vector(b); length=(b-a).length
    cap0=min(r0*.6,length*.3); cap1=min(r1*.6,length*.3)
    prof=[(0,0),(r0*.72,cap0*.25),(r0,cap0),(r1,length-cap1),(r1*.72,length-cap1*.25),(0,length)]
    side=Vector((0,0,1)) if abs((b-a).normalized().z)<.9 else Vector((1,0,0))
    return revolve(name,prof,mat,parent,n,a,b-a,side)

def block(name, p, size, mat, parent=None, yaw=0, bevel=.004):
    # Box rotated about the local Y axis (the bottle axis inside the hand rig).
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o=bpy.context.object
    o.scale=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler.z=math.radians(yaw)
    return finish(o,name,mat,parent,bevel)

def flame(parent, origin, axis, size, side=(1,0,0), n=7):
    # Teardrop flame: hot core inside a dirty-orange tongue, emissive.
    kw=dict(parent=parent,origin=origin,axis=axis,side=side,n=n)
    revolve('Flame',[(0,-.2*size),(.5*size,0),(.62*size,.5*size),(.4*size,1.3*size),(0,2.3*size)],FLAMEOUT,**kw)
    revolve('Flame core',[(0,-.1*size),(.28*size,.1*size),(.32*size,.5*size),(.16*size,.95*size),(0,1.35*size)],FLAMEIN,**kw)

BOTTLE_HEIGHT=.25
BOTTLE_RADIUS=.0338
def bottle(parent, origin=(0,0,0), axis=(0,1,0), side=(1,0,0), label_arc=(math.radians(40),math.radians(220))):
    # Generic Czech half-litre returnable bottle: squat shoulder, long neck,
    # foil-wrapped neck, crimped crown cap and an unbranded paper label.
    kw=dict(parent=parent,origin=origin,axis=axis,side=side)
    revolve('Bottle',[(0,.002),(.029,0),(.0332,.005),(BOTTLE_RADIUS,.012),(BOTTLE_RADIUS,.14),(.0325,.155),(.0285,.17),
                      (.0225,.184),(.0172,.196),(.0138,.208),(.0134,.232),(.0153,.234),(.0153,.241),(.0136,.242),(0,.242)],GLASS,n=18,**kw)
    revolve('Crown cap',[(.0148,.2395),(.0168,.2405),(.0168,.2475),(.0128,.2515),(0,.2515)],CAP,n=21,
            ripple=lambda i:1.0 if i%2 else 1.08,**kw)
    revolve('Neck foil',[(.0145,.209),(.0141,.227)],FOIL,n=18,**kw)
    revolve('Neck label',[(.0225,.186),(.0185,.195)],LABEL,n=18,**kw)
    revolve('Body label',[(BOTTLE_RADIUS+.0007,.092),(BOTTLE_RADIUS+.0007,.138)],LABEL,n=14,arc=label_arc,**kw)
    revolve('Label band',[(BOTTLE_RADIUS+.0012,.127),(BOTTLE_RADIUS+.0012,.133)],PRINT,n=14,arc=label_arc,**kw)
    mid=(label_arc[0]+label_arc[1])/2
    revolve('Label badge',[(BOTTLE_RADIUS+.0012,.1),(BOTTLE_RADIUS+.0016,.106),(BOTTLE_RADIUS+.0016,.116),(BOTTLE_RADIUS+.0012,.121)],PRINT,
            n=4,arc=(mid-.42,mid+.42),**kw)

def finger(rig, y, length, radius, start=6, bend=(60,56,50)):
    # Phalanges wrap the bottle from the palm (+X) round the far side; the knit
    # glove stops at the first joint, leaving grimy bare fingers and nails.
    ring=BOTTLE_RADIUS+radius+.0016
    angles=[start]; heights=[y]
    for k,step in enumerate(bend):
        angles.append(angles[-1]-step*length); heights.append(y+.0012*(k+1))
    pts=[Vector((math.cos(math.radians(a))*ring,h,math.sin(math.radians(a))*ring)) for a,h in zip(angles,heights)]
    pts[0]+=Vector((.009,0,0))
    mats=(WOOL,SKIN,SKIN)
    for k in range(3):
        r0=radius*(1.12 if k==0 else 1.0-.07*k); r1=radius*(1.0-.07*(k+1))
        limb('Finger',pts[k],pts[k+1],r0,r1,mats[k],rig)
    limb('Glove finger hem',pts[0].lerp(pts[1],.78),pts[0].lerp(pts[1],.98),radius*1.2,radius*1.2,WOOL,rig)
    tip=math.radians(angles[-1]+9); out=Vector((math.cos(tip),0,math.sin(tip)))
    block('Nail',Vector((0,heights[-1],0))+out*(ring+radius*.78),(.009,.0085,.003),NAIL,rig,yaw=-(angles[-1]+9+90),bevel=.0012)

class Rig:
    # A hand authored around a cylinder of BOTTLE_RADIUS on local +Y; the rig
    # places that cylinder in view space (base, axis) with the palm toward +X.
    # First-person scale is exaggerated so the hand reads above the HUD.
    def __init__(self, base, axis, scale=1.1, palm=(1,0,.25)):
        self.base=Vector(base); self.axis=Vector(axis).normalized(); self.scale=scale
        p=Vector(palm); self.palm=(p-self.axis*p.dot(self.axis)).normalized(); self.near=self.palm.cross(self.axis)
        self.node=bpy.data.objects.new('Hand',None); bpy.context.collection.objects.link(self.node); self.node.parent=ROOT
        swap=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
        self.node.matrix_world=(swap@Matrix((self.palm,self.axis,self.near)).transposed()@swap.transposed()).to_4x4()
        self.node.location=xyz(self.base); self.node.scale=(scale,)*3

    def point(self, local):
        l=Vector(local)
        return self.base+(self.palm*l.x+self.axis*l.y+self.near*l.z)*self.scale

def fist(hand):
    rig=hand.node
    # Four fingers from index (top) to little finger, stacked up the grip.
    for k,(length,radius) in enumerate([(1.0,.0088),(1.06,.0092),(.98,.0088),(.82,.0076)]):
        finger(rig,.084-k*.0195,length,radius,start=6+k*2)
    # Knitted back of the hand, knuckle ridge and the thenar pad (thin side radial).
    block('Glove back',(BOTTLE_RADIUS+.024,.053,.006),(.032,.086,.064),WOOL,rig,yaw=-8,bevel=.013)
    block('Knuckle ridge',(BOTTLE_RADIUS+.016,.054,-.016),(.022,.08,.03),WOOL,rig,yaw=18,bevel=.009)
    block('Thenar pad',(BOTTLE_RADIUS+.012,.04,.026),(.03,.05,.03),WOOL,rig,yaw=-30,bevel=.011)
    for k in range(5):
        block('Glove rib',(BOTTLE_RADIUS+.0405,.02+k*.016,.006),(.003,.004,.06),JACKET,rig,yaw=-8,bevel=.0012)
    # Thumb rounds the near side of the grip toward the camera.
    ring=BOTTLE_RADIUS+.0095
    t=[Vector((math.cos(math.radians(a))*r,h,math.sin(math.radians(a))*r)) for a,h,r in
       [(28,.034,ring+.012),(66,.056,ring+.001),(104,.076,ring),(138,.091,ring)]]
    limb('Thumb',t[0],t[1],.0118,.0108,WOOL,rig)
    limb('Thumb',t[1],t[2],.0106,.0098,SKIN,rig)
    limb('Thumb',t[2],t[3],.0098,.0088,SKIN,rig)
    tip=math.radians(146); out=Vector((math.cos(tip),0,math.sin(tip)))
    block('Nail',Vector((0,.093,0))+out*(ring+.0072),(.01,.009,.003),NAIL,rig,yaw=-(146+90),bevel=.0012)
    # Wrist, knitted cuff and a frayed jacket sleeve leaving the palm side,
    # down the grip and toward the camera, out of frame.
    wrist=Vector((BOTTLE_RADIUS+.034,.04,.012))
    local=Vector((.8,-.75,.6)).normalized()
    limb('Wrist',wrist-local*.02,wrist+local*.07,.03,.028,WOOL,rig)
    limb('Glove cuff',wrist+local*.045,wrist+local*.1,.032,.033,JACKET,rig,n=12)
    limb('Sleeve',wrist+local*.085,wrist+local*.4,.043,.052,JACKET,rig,n=12)
    limb('Sleeve hem',wrist+local*.082,wrist+local*.1,.046,.047,WOOL,rig,n=12)

def handle(rig, y0=-.012, y1=.125):
    # Pipe grip under the glove: bare iron between sloppy tape wraps.
    R=BOTTLE_RADIUS; rig=rig.node
    rod('Grip pipe',(0,y0,0),(0,y1,0),R,R,DARKIRON,12,rig,smooth=True)
    for k,y in enumerate((y0+.012,.015,.04,.065,.09,.115)):
        rod('Grip tape',(0,y-.0095,0),(0,y+.0095,0),R+.002,R+.002,DUCT if k==2 else GAFFER,12,rig,smooth=True)

def tape(a, b, r, mat=GAFFER, n=10, parent=None):
    return rod('Tape wrap',a,b,r,r,mat,n,parent)

MUZZLES={}
EJECT={}
AIM_Y=.062

def beer():
    # Bottle base, axis and palm direction in view space.
    rig=Rig((.01,.01,-.02),(-.267,.79,-.55))
    bottle(rig.node)
    fist(rig)
    # Thrown copy, centred on its origin with the neck along -Z (flight axis).
    flying=bpy.data.objects.new('ThrownBottle',None); bpy.context.collection.objects.link(flying); flying.parent=ROOT
    bottle(flying,origin=(0,0,BOTTLE_HEIGHT/2),axis=(0,0,-1),side=(1,0,0),label_arc=(0,math.tau))
    MUZZLES['pulse']=tuple(rig.base+rig.axis*BOTTLE_HEIGHT*rig.scale)

def empty(name, p=(0,0,0), parent=None):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.parent=parent or ROOT; o.location=xyz(p)
    return o

def rebar(a, b, r, mat=RUST, ribs=True, step=.05, parent=None):
    # Hex-section rebar with ring ribs; used for both the gun and its spike.
    a=Vector(a); b=Vector(b); d=b-a; length=d.length; d=d.normalized()
    rod('Rebar',a,b,r,r,mat,6,parent)
    if ribs:
        for k in range(int(length/step)):
            p=a+d*(step*(k+.5))
            rod('Rebar rib',p-d*.004,p+d*.004,r*1.38,r*1.38,RUSTDARK,6,parent)

def excalibur():
    # Rail: a rusty rebar "sword" shoved through a gaffer-taped pipe, with a bent
    # road-sign crossguard and a toilet brush strapped to the side.
    y=AIM_Y
    rig=Rig((.045,-.075,.06),(-.08,.85,-.52)); fist(rig); handle(rig)
    pipe('Sleeve pipe',(0,y,.14),(0,y,-.3),.037,.03,IRON,10)
    for z in (.11,.03,-.06,-.17,-.26):
        tape((0,y,z+.017),(0,y,z-.017),.0405,GAFFER if z>-.1 else DUCT)
    rod('Pommel nut',(0,y,.14),(0,y,.162),.047,.047,RUSTDARK,6)
    rod('Pommel bolt',(0,y,.162),(0,y,.176),.021,.021,RUST,6)
    tip=(0,y,-1.0)
    rebar((0,y,.16),(0,y,-.94),.0125,RUST,True,.052)
    rod('Sharpened tip',(0,y,-.94),tip,.0125,.0005,IRON,6)
    # Bent road-sign crossguard: red paint, dirty-white stripes, two bolts.
    zc=-.325
    slab('Guard centre',(0,y,zc),(.1,.045,.012),SIGNRED)
    for s in (-1,1):
        d=Vector((s*math.cos(math.radians(20)),0,-math.sin(math.radians(20))))
        c=Vector((s*.05,y,zc))+d*.075
        slab('Guard wing',c,(.15,.045,.012),SIGNRED,rot=(0,s*20,0))
        slab('Guard stripe',c+d*.01,(.028,.046,.0135),BONE,rot=(0,s*20,0))
        slab('Guard stripe',c-d*.04,(.02,.046,.0135),BONE,rot=(0,s*20,0))
        rod('Guard bolt',(s*.025,y+.026,zc),(s*.025,y+.036,zc),.007,.007,IRON,6)
    # Toilet brush: bone-white handle taped alongside, grubby bristle head in front.
    bx=-.068
    rod('Brush handle',(bx,.03,.1),(bx,.034,-.39),.0105,.0105,BONE,8)
    for z in (.07,-.04,-.2):
        tape((bx,.031,z+.015),(bx,.031,z-.015),.016,GAFFER if z>-.1 else DUCT)
    rod('Brush cup',(bx,.034,-.375),(bx,.034,-.43),.024,.03,BONE,8)
    blob('Brush bristles',(bx,.034,-.5),(.048,.048,.08),BRISTLE,segments=7,rings=4)
    # Rebar spike flung at the target: roll-spinning with taped flights.
    spike=empty('ThrownSpike')
    rod('Spike',(0,0,.34),(0,0,-.3),.0125,.0125,RUST,6,spike)
    rod('Spike point',(0,0,-.3),(0,0,-.4),.0125,.0005,IRON,6,spike)
    for k in range(10):
        z=.3-k*.062
        rod('Spike rib',(0,0,z+.004),(0,0,z-.004),.0175,.0175,RUSTDARK,6,spike)
    slab('Flight tape',(0,0,.31),(.085,.003,.07),DUCT,parent=spike)
    slab('Flight tape',(0,0,.31),(.003,.085,.07),SIGNRED,parent=spike)
    MUZZLES['rail']=tip

def record(parent, c, normal, r):
    # 12-inch-ish record: black vinyl, grooved sheen rings, orange label with
    # an off-centre bone stripe so its spin reads.
    n=Vector(normal).normalized(); c=Vector(c)
    disc('Vinyl',c,n,r,.006,VINYL,20,parent)
    for k,(a,b) in enumerate(((.5,.62),(.72,.86))):
        ring_pipe('Groove sheen',c+n*.0035,n,r*b,r*a,.002,GROOVE,20,parent)
        ring_pipe('Groove sheen',c-n*.0035,n,r*b,r*a,.002,GROOVE,20,parent)
    for s in (-1,1):
        disc('Label',c+n*s*.0036,n,r*.3,.0016,VLABEL,12,parent)
    u,_,_=frame(n)
    for s in (-1,1):
        disc('Label mark',c+n*s*.0044+u*r*.18,n,r*.09,.0016,BONE,8,parent)

def vinyly():
    # Scatter: record-player plinth with a tonearm, a taped pipe barrel, a
    # record-sleeve pump and a fan of spare records on the left.
    y=AIM_Y
    rig=Rig((.045,-.075,.07),(-.08,.85,-.52)); fist(rig); handle(rig)
    slab('Plinth',(0,y-.002,-.02),(.12,.075,.36),WOOD)
    slab('Plinth lip',(0,y-.0415,-.02),(.128,.008,.368),DARKIRON)
    slab('Plinth split',(.03,y+.0375,.0),(.05,.002,.18),RUSTDARK)
    pipe('Barrel',(0,y+.005,-.14),(0,y+.005,-.62),.032,.024,IRON,10)
    for z in (-.2,-.34,-.56):
        tape((0,y+.005,z+.017),(0,y+.005,z-.017),.0355,GAFFER if z>-.3 else DUCT)
    rod('Barrel mouth ring',(0,y+.005,-.605),(0,y+.005,-.62),.038,.038,RUSTDARK,10,caps=(True,False))
    # Platter with a record on it, spindle, and the tonearm over it.
    disc('Platter',(-.012,y+.04,.03),(0,1,0),.05,.008,DARKIRON,16)
    record(None,(-.012,y+.047,.03),(0,1,0),.046)
    rod('Spindle',(-.012,y+.047,.03),(-.012,y+.07,.03),.004,.002,IRON,6)
    rod('Tonearm pivot',(.05,y+.038,.11),(.05,y+.07,.11),.017,.014,IRON,8)
    rod('Tonearm cap',(.05,y+.07,.11),(.05,y+.074,.11),.01,.01,BONE,8)
    a=Vector((.05,y+.072,.11)); b=Vector((.014,y+.066,-.07))
    rod('Tonearm',a,b,.0045,.0045,IRON,6)
    rod('Tonearm counterweight',a+(a-b).normalized()*.015,a+(a-b).normalized()*.05,.016,.016,DARKIRON,8)
    slab('Headshell',b+Vector((-.002,-.002,-.018)),(.018,.006,.045),BONE,rot=(0,-6,0))
    slab('Cartridge',b+Vector((-.002,-.012,-.02)),(.012,.012,.02),SIGNRED)
    for x,z in ((-.035,.14),(.035,-.13)):
        rod('Plinth knob',(x,y+.0375,z),(x,y+.05,z),.011,.011,IRON,8)
    # Spare records fanned open like pages in a taped holder, left of the barrel.
    for k,ang in enumerate((32,52,72,92)):
        t=math.radians(ang)
        n=Vector((-math.sin(t),.12,math.cos(t))); d=Vector((-math.cos(t),0,-math.sin(t)))
        record(None,Vector((-.11,y-.012,.01))+d*.062+Vector((0,.05,0)),n,.062)
    rod('Record holder',(-.11,y-.065,.01),(-.11,y+.065,.01),.007,.007,IRON,6)
    tape((-.11,y-.04,.01),(-.11,y-.015,.01),.012,DUCT)
    # Pump: a wooden sleeve forend between two record flanges; slides when fired.
    pump=empty('Pump')
    slab('Forend',(0,y-.036,-.38),(.075,.05,.19),WOOD,parent=pump)
    for z in (-.285,-.475):
        disc('Forend flange',(0,y-.036,z),(0,0,1),.052,.006,VINYL,16,pump)
        disc('Forend flange label',(0,y-.036,z+.0035),(0,0,1),.02,.002,VLABEL,10,pump)
    tape((0,y-.036,-.37),(0,y-.036,-.39),.043,GAFFER,10,pump)
    # Flying record, tilted so its spin wobbles when seen from behind.
    t=empty('ThrownDisc')
    record(t,(0,0,0),(0,.28,.96),.075)
    MUZZLES['scatter']=(0,y+.005,-.625)

def pigeon(parent):
    # Low-poly pigeon (flight axis -Z) with flappable wing pivots WingL/WingR.
    blob('Pigeon body',(0,0,0),(.03,.028,.07),PIGEON,segments=8,rings=5,parent=parent)
    blob('Pigeon neck',(0,.014,-.056),(.022,.022,.03),SHEEN,segments=7,rings=4,parent=parent)
    blob('Pigeon head',(0,.026,-.082),(.016,.016,.02),PIGEON,segments=7,rings=4,parent=parent)
    rod('Pigeon beak',(0,.024,-.099),(0,.022,-.123),.0065,.0006,BEAK,5,parent)
    for s in (-1,1):
        blob('Pigeon eye',(s*.011,.03,-.09),(.0045,.0045,.0045),EYE,segments=5,rings=3,parent=parent)
    slab('Pigeon tail',(0,.0,.1),(.06,.008,.075),PIGEONDARK,rot=(-4,0,0),parent=parent,taper=.7)
    for s,name in ((-1,'WingL'),(1,'WingR')):
        w=empty(name,(s*.02,.016,-.005),parent)
        slab('Pigeon wing',(s*.065,.0,.006),(.12,.006,.09),PIGEONDARK,rot=(0,-s*9,0),parent=w,taper=1.0)
        slab('Pigeon wing tip',(s*.145,.0,.03),(.06,.006,.07),PIGEONDARK,rot=(0,-s*16,0),parent=w,taper=.7)

def holubi():
    # Minigun: a bike wheel spun by a rusty fan motor, six taped tin cans for
    # barrels, a cardboard box feeding bread rolls; pigeons are the bullets.
    ay=.056
    rig=Rig((.045,-.075,.07),(-.08,.85,-.52)); fist(rig); handle(rig)
    rod('Motor housing',(0,ay,.12),(0,ay,-.08),.05,.05,RUST,10)
    for z in (.1,.04,-.02):
        tape((0,ay,z+.014),(0,ay,z-.014),.0525,GAFFER if z<0 else DUCT)
    rod('Motor back plate',(0,ay,.12),(0,ay,.135),.035,.035,DARKIRON,8)
    # Bread box: cardboard crate on the left, bread rolls riding a duct-tape belt.
    slab('Bread box',(-.115,ay-.045,-.025),(.095,.085,.15),BOARD,rot=(0,0,0))
    slab('Bread box flap',(-.115,ay,-.06),(.095,.004,.08),BOARD,rot=(-24,0,0))
    slab('Box tape',(-.115,ay-.0,-.0),(.1,.006,.03),DUCT)
    slab('Belt',(-.07,ay+.02,-.01),(.09,.01,.03),DUCT,rot=(0,0,-22))
    for k,(bx,by,bz) in enumerate(((-.108,.0,-.04),(-.082,.012,-.025),(-.056,.02,-.012),(-.03,.028,.0))):
        blob('Bread roll',(bx,ay+by+.015,bz),(.014,.013,.033),BREAD,rot=(0,0,0),segments=7,rings=4)
        slab('Bread slit',(bx,ay+by+.027,bz),(.004,.003,.045),BREADCUT)
    # Spinning assembly: bike wheel with spokes and tyre, six tin-can barrels.
    spin=empty('Spinner',(0,ay,0))
    zw=-.095
    torus('Bike rim',(0,0,zw),(0,0,1),.118,.006,IRON,20,5,spin)
    torus('Bike tyre',(0,0,zw),(0,0,1),.128,.0145,RUBBERTYRE,20,6,spin)
    rod('Hub',(0,0,zw+.03),(0,0,zw-.03),.022,.022,IRON,8,spin)
    rod('Axle',(0,0,zw+.06),(0,0,-.41),.009,.009,DARKIRON,6,spin)
    for k in range(16):
        a=math.tau*k/16; d=Vector((math.cos(a),math.sin(a),0))
        z=.006 if k%2 else -.006
        rod('Spoke',Vector((0,0,zw+z))+d*.022,Vector((0,0,zw+z*.4))+d*.118,.0026,.0026,IRON,4,spin)
    for k in range(6):
        a=math.tau*(k+.5)/6; x=math.cos(a)*.072; yy=math.sin(a)*.072
        pipe('Barrel can',(x,yy,zw-.03),(x,yy,-.23),.026,.0225,TIN,8,spin)
        pipe('Barrel can',(x,yy,-.235),(x,yy,-.4),.026,.0205,TIN if k%2 else RUST,8,spin)
        tape((x,yy,-.232-.012),(x,yy,-.232+.012),.0275,GAFFER,8,spin)
    torus('Barrel strap',(0,0,-.18),(0,0,1),.088,.0045,DUCT,16,4,spin)
    torus('Barrel strap',(0,0,-.37),(0,0,1),.088,.0045,DUCT,16,4,spin)
    # Flying pigeon, nose toward -Z.
    p=empty('ThrownPigeon')
    pigeon(p)
    MUZZLES['minigun']=(0,ay,-.42)
    EJECT['minigun']=(.052,ay-.02,-.0)

def absinthe(parent, origin=(0,0,0), axis=(0,1,0), side=(1,0,0), label_arc=(math.radians(40),math.radians(220))):
    # Dark green wine-shaped bottle with a cream label and a stuffed oily rag.
    kw=dict(parent=parent,origin=origin,axis=axis,side=side)
    revolve('Absinth bottle',[(0,.002),(.026,0),(.03,.007),(.03,.15),(.027,.168),(.02,.188),(.0135,.206),(.0125,.265),
                              (.0146,.268),(.0146,.276),(.0127,.277),(0,.277)],ABSINTH,n=10,smooth=False,**kw)
    revolve('Absinth label',[(.0305,.07),(.0305,.128)],BONE,n=10,arc=label_arc,smooth=False,**kw)
    revolve('Absinth label band',[(.0309,.1),(.0309,.108)],DARKIRON,n=10,arc=label_arc,smooth=False,**kw)
    revolve('Absinth rag',[(0,.255),(.008,.262),(.0125,.285),(.011,.31),(.005,.335),(0,.345)],RAG,n=7,smooth=False,**kw)

def molotov():
    # Autocannon: a drainpipe mortar with a lit absinth molotov stuffed in the
    # mouth, fed from a cardboard box of more bottles on the left.
    y=.074
    rig=Rig((.045,-.07,.06),(-.08,.85,-.52)); fist(rig); handle(rig)
    pipe('Drainpipe',(0,y,.06),(0,y,-.46),.058,.046,IRON,12)
    for z in (.03,-.07,-.18,-.3,-.42):
        tape((0,y,z+.02),(0,y,z-.02),.0615,GAFFER if z>-.1 else DUCT,12)
    rod('Pipe socket',(0,y,.06),(0,y,.015),.07,.07,RUSTDARK,12)
    # The loaded bottle's neck, rag and flame show from the mouth.
    absinthe(None,origin=(0,y,-.25),axis=(0,0,-1),side=(1,0,0))
    pilot=empty('Pilot',(0,y,-.25-.335))
    flame(pilot,(0,0,0),(0,0,-1),.026)
    # Cardboard box of spare bottles, lying neck-forward on the right of the pipe.
    slab('Bottle box',(.135,y-.03,-.04),(.1,.01,.27),BOARD)
    slab('Bottle box wall',(.188,y+.0,-.04),(.01,.07,.27),BOARD)
    for bx,by in ((.115,.012),(.155,.012),(.135,.062)):
        absinthe(None,origin=(bx,y+by,.09),axis=(0,0,-1),side=(1,0,0))
    for z in (-.0,-.12):
        tape((.135,y+.02,z+.012),(.135,y+.02,z-.012),.052,DUCT,8)
    # Flying bottle: neck forward, lit rag trailing a flame.
    t=empty('ThrownMolotov')
    absinthe(t,origin=(0,0,.14),axis=(0,0,-1),side=(1,0,0),label_arc=(0,math.tau))
    flame(t,(0,0,.14-.335),(0,0,-1),.026)
    # Blast and rim vessels are authored in the scene; the muzzle is the flame.
    MUZZLES['autocannon']=(0,y,-.25-.335-.03)

def hairspray(rig):
    # The grip itself is a hairspray can in the hand, cap and nozzle on top.
    kw=dict(parent=rig.node,origin=(0,0,0),axis=(0,1,0),side=(1,0,0))
    R=BOTTLE_RADIUS
    revolve('Spray can',[(0,-.04),(R*.9,-.04),(R,-.032),(R,.15),(R*.9,.158),(R*.5,.165),(0,.165)],SPRAY,n=10,smooth=False,**kw)
    revolve('Spray label',[(R+.0012,.0),(R+.0012,.12)],SPRAYCAP,n=10,arc=(math.radians(-20),math.radians(150)),smooth=False,**kw)
    revolve('Spray cap',[(R*.82,.158),(R*.82,.2),(R*.62,.208),(0,.208)],SPRAYCAP,n=10,smooth=False,**kw)
    rod('Spray nozzle',(0,.205,0),(0,.226,0),.009,.007,BONE,8,rig.node)

def flamer():
    # Flamethrower: hairspray-can grip, a pipe to a taped-on lighter, and a
    # giant rum bottle strapped on as the "fuel tank".
    rig=Rig((.05,-.075,.07),(-.1,.6,-.8)); fist(rig); hairspray(rig)
    top=rig.point((0,.228,0)); y=top.y+.012
    pipe('Spray pipe',(top.x,y,top.z),(0,y,-.49),.0175,.011,IRON,8)
    rod('Spray elbow',(top.x,y-.012,top.z),(top.x,y+.012,top.z),.024,.024,DARKIRON,8)
    for z in (-.1,-.25,-.4):
        tape((0,y,z+.012),(0,y,z-.012),.0215,GAFFER if z<-.2 else DUCT,8)
    # Lighter taped to the end of the pipe: red body, brass hood, pilot flame.
    slab('Lighter',(.004,y-.012,-.47),(.026,.075,.014),LIGHTER,rot=(0,0,-7))
    slab('Lighter hood',(.004,y+.03,-.47),(.02,.014,.012),DUCT)
    tape((.004,y-.012,-.472+.014),(.004,y-.012,-.472-.014),.021,DUCT,6)
    pilot=empty('Pilot',(.0,y+.04,-.49))
    flame(pilot,(0,0,0),(0,1,0),.02,side=(1,0,0),n=6)
    # Giant rum bottle on its side, strapped over the left of the pipe.
    kw=dict(origin=(-.04,y-.05,.1),axis=(-.5,-.04,-.86),side=(0,1,0))
    revolve('Rum bottle',[(0,0),(.052,0),(.059,.012),(.059,.22),(.05,.245),(.024,.285),(.0175,.305),(.0175,.385),(.02,.39),(.02,.405),(0,.405)],RUMGLASS,n=10,smooth=False,**kw)
    revolve('Rum label',[(.0602,.06),(.0602,.17)],BONE,n=10,arc=(math.radians(20),math.radians(160)),smooth=False,**kw)
    revolve('Rum label band',[(.0606,.1),(.0606,.12)],SIGNRED,n=10,arc=(math.radians(20),math.radians(160)),smooth=False,**kw)
    revolve('Rum cork',[(.0185,.395),(.0185,.425),(0,.428)],BOARD,n=8,smooth=False,**kw)
    ax=Vector((-.5,-.04,-.86)).normalized(); o=Vector((-.04,y-.05,.1))
    for h in (.06,.17):
        tape(o+ax*(h-.014),o+ax*(h+.014),.0625,DUCT,10)
    slab('Pipe strap',(-.02,y-.02,-.03),(.06,.012,.03),GAFFER,rot=(0,0,-35))
    MUZZLES['flamethrower']=(0,y,-.505)

if __name__ == '__main__':
    builders = [('pulse',beer),('rail',excalibur),('scatter',vinyly),('minigun',holubi),('autocannon',molotov),('flamethrower',flamer)]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--weapon', action='append', choices=[kind for kind, _ in builders],
                        help='Build only this weapon; repeat to select several. Default: all.')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    for kind, build in builders:
        if args.weapon and kind not in args.weapon:
            continue
        bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
        ROOT=bpy.data.objects.new(kind,None); bpy.context.collection.objects.link(ROOT)
        if kind != 'pulse': ROOT.location=xyz(SHIFT)
        build()
        # Join static material batches; the moving Pump and Spinner assemblies
        # and every Thrown* projectile template (one mesh each) stay separate.
        # Geometry is authored once, not built at game startup.
        batches = {}
        for o in list(bpy.context.scene.objects):
            if o.type != 'MESH':
                continue
            if o.parent.name.startswith('Thrown'):
                key = (o.parent.name,)
            else:
                key = (o.parent.name, o.data.materials[0].name)
            batches.setdefault(key, []).append(o)
        for key, objects in batches.items():
            bpy.ops.object.select_all(action='DESELECT')
            for o in objects: o.select_set(True)
            active = objects[0]
            bpy.context.view_layer.objects.active = active
            if len(objects) > 1: bpy.ops.object.join()
            active.name = key[0][6:] if len(key) == 1 else 'Parts_' + key[1]
        markers = [('Muzzle',MUZZLES[kind])] + ([('Eject',EJECT[kind])] if kind in EJECT else [])
        for name,p in markers:
            empty(name,p)
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,kind+'.glb'),export_format='GLB',use_selection=True,export_apply=True)
        tris=sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
        print('GUN BUILT',kind,'polygons',tris,'muzzle in view space',tuple(round(a+b,3) for a,b in zip(MUZZLES[kind],SHIFT if kind != 'pulse' else (0,0,0))))
