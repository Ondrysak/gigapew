"""Original metre-scale gun assets. Run: blender -b --python tools/guns/build_guns.py
Rebuild only the bottles: blender -b --python tools/guns/build_guns.py -- --weapon pulse
Godot axes in authoring helpers: X right, Y up, -Z muzzle. No external assets.
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

STEEL = material('Parkerized steel', (.12,.15,.18), .82,.38)
EDGE = material('Machined steel', (.32,.37,.4), .85,.29)
BLACK = material('Graphite polymer', (.035,.045,.052), .12,.68)
RUBBER = material('Rubber', (.018,.022,.025), 0,.84)
TAN = material('Cerakote sand', (.34,.28,.19), .45,.48)
RED = material('Safety red', (.42,.06,.035), .3,.45)
BRASS = material('Brass', (.62,.39,.1), .75,.3)
GLOVE = material('Charcoal glove', (.075,.083,.078), 0,.87)
CYAN = material('Charge indicator', (.03,.65,.58), .3,.4,1)
AMBER = material('Pilot indicator', (1,.24,.018), .3,.4,1)
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

def box(name, p, size, mat=STEEL, bevel=.003, parent=None, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    o = bpy.context.object
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler.x = math.radians(angle)
    return finish(o,name,mat,parent,bevel)

def tube(name,p,r,length,mat=STEEL,inner=0,parent=None,axis='z'):
    # Open machined tube; inner bore is real geometry, never a black end cap.
    vertices=[]; faces=[]; n=24
    for z, radius in [(-length/2,r),(length/2,r),(-length/2,inner),(length/2,inner)]:
        for i in range(n):
            a=2*math.pi*i/n
            v=(math.cos(a)*radius,math.sin(a)*radius,z)
            if axis=='z': v=(v[0],v[1],v[2])
            elif axis=='y': v=(v[0],v[2],v[1])
            else: v=(v[2],v[0],v[1])
            vertices.append(xyz((p[0]+v[0],p[1]+v[1],p[2]+v[2])))
    for i in range(n):
        j=(i+1)%n
        faces.extend([(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),
                      (i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)])
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(vertices,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(o)
    finish(o,name,mat,parent)
    for poly in mesh.polygons: poly.use_smooth=True
    return o

def profile(name, points, width, mat=STEEL):
    # Extruded asymmetric receiver/grip/stock silhouettes in YZ plane.
    verts=[xyz((x,y,z)) for x in (-width/2,width/2) for y,z in points]
    n=len(points)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(o)
    return finish(o,name,mat,bevel=.002)

def rail(z0,z1,y,width=.065):
    box('Picatinny rail',(0,y,(z0+z1)/2),(width,.013,z1-z0),BLACK,.001)
    for i in range(int((z1-z0)/.025)):
        box('Rail tooth',(0,y+.013,z0+i*.025),(width,.012,.013),STEEL,.001)

def fasteners(zs,y=.035,x=.052):
    for z in zs:
        for side in (-1,1):
            tube('Torx fastener',(side*x,y,z),.005,.004,EDGE,.002,axis='x')

def sights(zfront,zrear,y=.12):
    for z in (zfront,zrear):
        box('Sight pedestal',(0,y-.022,z),(.045,.035,.025),STEEL)
        tube('Protected sight',(0,y+.012,z),.017,.015,BLACK,.012)
    box('Front post',(0,y+.012,zfront),(.003,.025,.005),EDGE,.001)

def grip(z=.035):
    profile('Pistol grip',[(.004,z-.04),(-.075,z-.025),(-.15,z+.025),(-.145,z+.075),(-.02,z+.05)],.055,BLACK)
    for i in range(5):
        box('Grip ribs',(0,-.065-i*.013,z+.021+i*.006),(.06,.005,.03),RUBBER,.001)
    # Trigger guard composed as an open frame, with a curved trigger inside.
    box('Trigger guard lower',(0,-.071,z-.065),(.028,.009,.1),STEEL,.002)
    box('Trigger guard front',(0,-.04,z-.11),(.025,.06,.01),STEEL,.002)
    box('Trigger',(0,-.04,z-.044),(.012,.04,.009),EDGE,.002,angle=-18)
    # Modelled glove palm and curled fingers, with knuckle seam pads.
    box('Glove palm',(.027,-.087,z+.035),(.054,.073,.059),GLOVE,.014,angle=-12)
    for i in range(4):
        box('Curled glove finger',(-.019,-.061-i*.018,z+.025+i*.006),(.062,.015,.029),GLOVE,.006)
        box('Knuckle pad',(.047,-.061-i*.018,z+.025),(.013,.014,.024),RUBBER,.004)
    box('Thumb',(.036,-.035,z+.012),(.023,.052,.032),GLOVE,.009,angle=28)
    box('Glove cuff',(.033,-.156,z+.055),(.071,.038,.069),BLACK,.008,angle=-12)

def magazine(z,depth=.12):
    mag = profile('Magazine',[(0,z-.038),(-depth*.45,z-.039),(-depth,z-.01),(-depth-.018,z+.052),(-.005,z+.038)],.054,BLACK)
    box('Magazine floorplate',(0,-depth-.012,z+.025),(.062,.018,.077),STEEL,parent=mag)
    for side in (-1,1):
        for i in range(3):
            box('Magazine groove',(side*.028,-depth*.55,z-.018+i*.018),(.002,depth*.68,.005),RUBBER,.001,parent=mag)

def butt(z=.28):
    tube('Buffer tube',(0,.029,(z+.06)/2),.023,z-.06,STEEL)
    profile('Adjustable stock',[(.074,z-.13),(.065,z+.025),(-.095,z+.025),(-.076,z-.05),(.005,z-.13)],.066,BLACK)
    box('Stock pad',(0,-.015,z+.026),(.079,.177,.021),RUBBER,.008)
    box('Stock cheek rest',(0,.071,z-.045),(.074,.025,.12),BLACK,.006)

def muzzle(z,r=.022):
    tube('Muzzle device',(0,.052,z+.025),r,.05,EDGE,r*.55)
    for i in range(3):
        tube('Muzzle ring',(0,.052,z+.007+i*.014),r*1.06,.005,STEEL,r*.55)

def revolve(name, prof, mat, parent=None, n=16, origin=(0,0,0), axis=(0,1,0), side=(1,0,0), arc=None, ripple=None):
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
    for poly in mesh.polygons: poly.use_smooth=True
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

MUZZLES={}
def beer():
    # Bottle base, axis and palm direction in view space; the rig keeps every
    # hand part authored around the bottle axis (local +Y). First-person scale
    # is exaggerated so the hand reads above the HUD.
    base=Vector((.01,.01,-.02)); axis=Vector((-.267,.79,-.55)).normalized(); scale=1.1
    palm=Vector((1,0,.25)); palm=(palm-axis*palm.dot(axis)).normalized(); near=palm.cross(axis)
    rig=bpy.data.objects.new('Hand',None); bpy.context.collection.objects.link(rig); rig.parent=ROOT
    swap=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
    rig.matrix_world=(swap@Matrix((palm,axis,near)).transposed()@swap.transposed()).to_4x4()
    rig.location=xyz(base); rig.scale=(scale,)*3
    bottle(rig)
    # Four fingers from index (top) to little finger, stacked up the body.
    for k,(length,radius) in enumerate([(1.0,.0088),(1.06,.0092),(.98,.0088),(.82,.0076)]):
        finger(rig,.084-k*.0195,length,radius,start=6+k*2)
    # Knitted back of the hand, knuckle ridge and the thenar pad (thin side radial).
    block('Glove back',(BOTTLE_RADIUS+.024,.053,.006),(.032,.086,.064),WOOL,rig,yaw=-8,bevel=.013)
    block('Knuckle ridge',(BOTTLE_RADIUS+.016,.054,-.016),(.022,.08,.03),WOOL,rig,yaw=18,bevel=.009)
    block('Thenar pad',(BOTTLE_RADIUS+.012,.04,.026),(.03,.05,.03),WOOL,rig,yaw=-30,bevel=.011)
    for k in range(5):
        block('Glove rib',(BOTTLE_RADIUS+.0405,.02+k*.016,.006),(.003,.004,.06),JACKET,rig,yaw=-8,bevel=.0012)
    # Thumb rounds the near side of the bottle toward the camera.
    ring=BOTTLE_RADIUS+.0095
    t=[Vector((math.cos(math.radians(a))*r,h,math.sin(math.radians(a))*r)) for a,h,r in
       [(28,.034,ring+.012),(66,.056,ring+.001),(104,.076,ring),(138,.091,ring)]]
    limb('Thumb',t[0],t[1],.0118,.0108,WOOL,rig)
    limb('Thumb',t[1],t[2],.0106,.0098,SKIN,rig)
    limb('Thumb',t[2],t[3],.0098,.0088,SKIN,rig)
    tip=math.radians(146); out=Vector((math.cos(tip),0,math.sin(tip)))
    block('Nail',Vector((0,.093,0))+out*(ring+.0072),(.01,.009,.003),NAIL,rig,yaw=-(146+90),bevel=.0012)
    # Wrist, knitted cuff and a frayed jacket sleeve leaving the palm side,
    # down the bottle and toward the camera, out of frame.
    wrist=Vector((BOTTLE_RADIUS+.034,.04,.012))
    local=Vector((.8,-.75,.6)).normalized()
    limb('Wrist',wrist-local*.02,wrist+local*.07,.03,.028,WOOL,rig)
    limb('Glove cuff',wrist+local*.045,wrist+local*.1,.032,.033,JACKET,rig,n=12)
    limb('Sleeve',wrist+local*.085,wrist+local*.4,.043,.052,JACKET,rig,n=12)
    limb('Sleeve hem',wrist+local*.082,wrist+local*.1,.046,.047,WOOL,rig,n=12)
    # Thrown copy, centred on its origin with the neck along -Z (flight axis).
    flying=bpy.data.objects.new('ThrownBottle',None); bpy.context.collection.objects.link(flying); flying.parent=ROOT
    bottle(flying,origin=(0,0,BOTTLE_HEIGHT/2),axis=(0,0,-1),side=(1,0,0),label_arc=(0,math.tau))
    MUZZLES['pulse']=tuple(base+axis*BOTTLE_HEIGHT*scale)

def railgun():
    profile('Bullpup chassis',[(.095,.2),(.097,-.33),(.063,-.38),(-.012,-.32),(-.09,.21)],.104,STEEL)
    grip(-.13); magazine(.1,.135)
    box('Butt pad',(0,-.003,.226),(.115,.207,.024),RUBBER,.009)
    tube('Heavy barrel',(0,.052,-.51),.024,.38,EDGE,.01)
    for i in range(8):
        z=-.34-i*.031
        tube('Accelerator collar',(0,.052,z),.042,.014,BLACK,.027)
        for s in (-1,1): box('Coil conductor',(s*.035,.053,z),(.014,.017,.018),CYAN,.002)
    muzzle(-.738,.03)
    rail(-.31,.165,.112,.07)
    box('Optic mount',(0,.144,-.04),(.056,.043,.137),BLACK)
    tube('Scope body',(0,.194,-.072),.027,.24,BLACK,.02)
    tube('Objective housing',(0,.194,-.192),.036,.045,STEEL,.025)
    tube('Scope ocular',(0,.194,.049),.031,.033,RUBBER,.022)
    box('Optic elevation turret',(0,.225,-.028),(.035,.023,.033),EDGE)
    fasteners([-.29,-.17,.08,.17],.042,.057)
    box('Ejection port',(.056,.049,.082),(.009,.043,.085),BLACK)
    MUZZLES['rail']=(0,.052,-.739)

def scatter():
    profile('Shotgun receiver',[(.088,.1),(.088,-.17),(.058,-.2),(-.015,-.16),(-.033,.062)],.072,STEEL)
    grip(.037); butt(.32)
    tube('Shotgun barrel',(0,.052,-.405),.021,.49,STEEL,.016)
    tube('Magazine tube',(0,.006,-.372),.019,.39,BLACK,.013)
    pump = bpy.data.objects.new('Pump',None)
    bpy.context.collection.objects.link(pump)
    pump.parent = ROOT
    for i in range(10):
        tube('Pump grip rib',(0,.006,-.26-i*.019),.032,.013,BLACK,.021,parent=pump)
    box('Pump slide',(0,-.012,-.347),(.065,.032,.18),BLACK,.009,parent=pump)
    tube('Barrel clamp',(0,.052,-.49),.028,.022,EDGE,.021)
    muzzle(-.674,.026); rail(-.15,.065,.097); sights(-.62,.055,.145)
    for i in range(5):
        z=-.115+i*.035
        tube('Side saddle shell',(-.05,.036,z),.012,.065,RED,axis='y')
        tube('Shell brass head',(-.05,.073,z),.013,.01,BRASS,axis='y')
    fasteners([-.13,.03],.04,.04)
    MUZZLES['scatter']=(0,.052,-.675)

def minigun():
    tube('Motor casing',(0,.034,-.023),.098,.24,STEEL)
    for i in range(8): tube('Motor cooling ring',(0,.034,.045-i*.022),.102,.008,BLACK,.089)
    grip(.075)
    box('Belt box',(-.11,-.066,-.058),(.116,.185,.206),TAN,.013)
    box('Belt feed throat',(-.078,.013,-.054),(.09,.05,.085),STEEL)
    for i in range(5): tube('Linked cartridge',(-.093-i*.012,.02,-.07),.009,.085,BRASS)
    box('Carry handle left',(-.054,.157,-.002),(.018,.095,.025),STEEL)
    box('Carry handle right',(.054,.157,-.002),(.018,.095,.025),STEEL)
    box('Carry handle grip',(0,.205,-.002),(.126,.028,.038),BLACK,.01)
    spin=bpy.data.objects.new('Spinner',None); bpy.context.collection.objects.link(spin); spin.parent=ROOT
    spin.location = xyz((0,.034,0))
    for i in range(6):
        a=i*math.tau/6; x=math.cos(a)*.052; y=math.sin(a)*.052
        tube('Rotating barrel',(x,y,-.388),.015,.5,STEEL,.008,parent=spin)
        tube('Barrel crown',(x,y,-.643),.018,.024,EDGE,.009,parent=spin)
    tube('Front spider',(0,0,-.584),.079,.023,BLACK,.024,parent=spin)
    tube('Rear spider',(0,0,-.206),.079,.03,EDGE,.021,parent=spin)
    box('Motor controller',(.094,.032,-.024),(.037,.083,.103),BLACK)
    MUZZLES['minigun']=(0,.034,-.66)

def autocannon():
    profile('Cannon receiver',[(.132,.155),(.125,-.29),(.078,-.36),(-.038,-.29),(-.045,.15)],.119,TAN)
    grip(-.075)
    box('Butt pad',(0,.028,.187),(.128,.202,.026),RUBBER,.01)
    magazine(.06,.19)
    tube('Recoil sleeve',(0,.079,-.36),.044,.19,STEEL,.031)
    tube('20mm barrel',(0,.079,-.496),.028,.23,EDGE,.014)
    # Open ladder-style muzzle brake with side gas ports.
    for side in (-1,1): box('Brake wall',(side*.045,.079,-.645),(.013,.077,.113),STEEL)
    for z in (-.694,-.646,-.596):
        for y in (.041,.117): box('Brake bridge',(0,y,z),(.09,.012,.018),EDGE)
    rail(-.29,.13,.143,.077); sights(-.27,.09,.198)
    box('Charging lever',(.079,.067,.04),(.072,.02,.024),BLACK)
    for side in (-1,1):
        for i in range(5): box('Cooling fin',(side*.065,.073,-.17-i*.022),(.013,.081,.011),STEEL)
    fasteners([-.25,-.12,.06,.12],.059,.068)
    MUZZLES['autocannon']=(0,.079,-.703)

def flamethrower():
    profile('Wand receiver',[(.086,.1),(.079,-.19),(.025,-.27),(-.017,-.19),(-.023,.083)],.076,STEEL)
    grip(.015)
    tube('Fuel cylinder',(0,-.028,.17),.07,.232,TAN,axis='y')
    for y in (-.15,.084): tube('Tank band',(0,y,.17),.075,.024,STEEL,.066,axis='y')
    box('Pressure valve',(0,.105,.17),(.03,.029,.056),BRASS)
    tube('Pressure dial',(.058,.05,.167),.019,.012,EDGE,.014,axis='x')
    tube('Wand barrel',(0,.041,-.359),.025,.3,STEEL,.019)
    for i in range(9): tube('Nozzle heat ring',(0,.041,-.338-i*.021),.038,.009,EDGE,.025)
    for side in (-1,1): box('Nozzle heat shield',(side*.04,.037,-.43),(.012,.086,.207),BLACK)
    tube('Nozzle crown',(0,.041,-.572),.043,.052,STEEL,.028)
    tube('Fuel feed',(.045,-.01,-.238),.008,.39,BRASS,.003)
    box('Pilot igniter',(.019,.004,-.584),(.017,.016,.035),AMBER)
    rail(-.16,.056,.098,.055)
    fasteners([-.13,-.06,.06],.044,.043)
    MUZZLES['flamethrower']=(0,.041,-.6)

if __name__ == '__main__':
    builders = [('pulse',beer),('rail',railgun),('scatter',scatter),('minigun',minigun),('autocannon',autocannon),('flamethrower',flamethrower)]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--weapon', action='append', choices=[kind for kind, _ in builders],
                        help='Build only this weapon; repeat to select several. Default: all.')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    for kind, build in builders:
        if args.weapon and kind not in args.weapon:
            continue
        bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
        ROOT=bpy.data.objects.new(kind,None); bpy.context.collection.objects.link(ROOT)
        build()
        # Join static material batches; retain moving Magazine, Pump and Spinner
        # assemblies and the ThrownBottle projectile template (one mesh).
        # Geometry is authored once, not built at game startup.
        batches = {}
        for o in list(bpy.context.scene.objects):
            if o.type != 'MESH':
                continue
            if o.name == 'Magazine' or (o.parent and o.parent.name == 'Magazine'):
                key = ('Magazine',)
            elif o.parent.name == 'ThrownBottle':
                key = ('ThrownBottle',)
            else:
                key = (o.parent.name, o.data.materials[0].name)
            batches.setdefault(key, []).append(o)
        for key, objects in batches.items():
            bpy.ops.object.select_all(action='DESELECT')
            for o in objects: o.select_set(True)
            active = next((o for o in objects if o.name == 'Magazine'), objects[0])
            bpy.context.view_layer.objects.active = active
            if len(objects) > 1: bpy.ops.object.join()
            active.name = {('Magazine',): 'Magazine', ('ThrownBottle',): 'Bottle'}.get(key) or 'Parts_' + key[1]
        # Thrown bottles eject no casings.
        markers = [('Muzzle',MUZZLES[kind])] + ([] if kind == 'pulse' else [('Eject',(.058,.044,-.06))])
        for name,p in markers:
            o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.parent=ROOT; o.location=xyz(p)
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,kind+'.glb'),export_format='GLB',use_selection=True,export_apply=True)
        tris=sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
        print('GUN BUILT',kind,'polygons',tris,'muzzle',MUZZLES[kind])
