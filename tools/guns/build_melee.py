"""Original metre-scale melee assets; never exports the six firearm models.
Run from repo root: blender -b --python tools/guns/build_melee.py
Godot axes: X right, Y up, -Z forward. Grip pivot is at the origin.
"""
from pathlib import Path
import math
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_guns as geo

OUT = Path(__file__).resolve().parents[2] / 'assets' / 'melee'
TIPS = {'baton': (0, .54, -.08), 'cleaver': (0, .48, -.24)}


def held_grip(accent):
    """A reachable closed fist around a vertical rubber grip, with a cuff."""
    geo.tube('Grip core', (0, .015, 0), .023, .20, geo.BLACK, axis='y')
    for i in range(10):
        geo.tube('Rubber grip ring', (0, -.074 + i * .018, 0), .027, .012,
                 geo.RUBBER, axis='y')
    geo.tube('Grip end cap', (0, -.093, 0), .03, .016, geo.STEEL, axis='y')
    geo.box('Glove palm', (.031, -.018, .024), (.052, .083, .068),
            geo.GLOVE, .013)
    for i in range(4):
        y = .019 - i * .023
        geo.box('Curled glove finger', (-.012, y, -.021), (.07, .019, .031),
                geo.GLOVE, .007)
        geo.box('Finger return', (-.035, y, .007), (.022, .019, .046),
                geo.GLOVE, .007)
        geo.box('Knuckle pad', (.06, y, .004), (.014, .018, .029),
                geo.RUBBER, .004)
    geo.box('Glove thumb', (.036, .057, -.009), (.025, .061, .037),
            geo.GLOVE, .008, angle=24)
    geo.box('Glove cuff', (.031, -.095, .033), (.078, .045, .085),
            geo.BLACK, .009)
    geo.box('Cuff seam', (.071, -.095, .035), (.006, .017, .055), accent, .002)


def baton():
    held_grip(geo.CYAN)
    geo.box('Battery collar', (0, .13, -.012), (.077, .046, .078), geo.STEEL, .008)
    geo.box('Safety switch', (.042, .132, -.016), (.012, .022, .029), geo.RED, .003)
    geo.box('Charge gauge', (.041, .166, -.037), (.01, .029, .024), geo.CYAN, .002)
    geo.profile('Bent industrial neck', [(.14, .013), (.195, -.034),
                (.252, -.054), (.247, -.101), (.18, -.077), (.14, -.05)],
                .043, geo.STEEL)
    geo.tube('Insulated spine', (0, .365, -.08), .026, .32, geo.BLACK, axis='y')
    # Open protective cage: electrode light is visible between real metal rails.
    for y in (.235, .38, .525):
        geo.tube('Cage ring', (0, y, -.08), .055, .018, geo.EDGE, .042, axis='y')
    for i in range(4):
        a = i * math.tau / 4 + math.pi / 4
        x, z = math.cos(a) * .044, -.08 + math.sin(a) * .044
        geo.box('Cage rail', (x, .38, z), (.013, .29, .013), geo.STEEL, .003)
    for i in range(3):
        a = i * math.tau / 3
        x, z = math.cos(a) * .029, -.08 + math.sin(a) * .029
        geo.tube('Cyan electrode', (x, .383, z), .008, .266, geo.CYAN, axis='y')
    geo.tube('Shock crown', (0, .533, -.08), .041, .014, geo.EDGE, .023, axis='y')
    geo.tube('Crown electrode', (0, .537, -.08), .021, .006, geo.CYAN, axis='y')
    for x in (-.025, .025):
        geo.tube('Collar fastener', (x, .133, -.053), .005, .005, geo.EDGE)


def cleaver():
    held_grip(geo.TAN)
    geo.box('Orange grip collar', (0, .114, 0), (.07, .035, .064), geo.TAN, .005)
    geo.box('Finger guard', (0, .145, -.016), (.104, .025, .14), geo.STEEL, .006)
    geo.profile('Full tang', [(.12, .025), (.24, .035), (.25, -.023), (.12, -.027)],
                .023, geo.BLACK)
    # Asymmetric blade has a real open notch in the spine, not a painted decal.
    outline = [(.19, .028), (.28, .071), (.34, .073), (.344, .026),
               (.38, .028), (.388, .077), (.48, .071), (.515, -.192),
               (.48, -.24), (.228, -.21), (.19, -.11)]
    geo.profile('Beveled cleaver blade', outline, .043, geo.EDGE)
    # Narrow honed strip follows the cutting silhouette, with a thin sharp edge.
    geo.profile('Honed cutting edge', [(.515, -.192), (.48, -.24),
                (.228, -.21), (.19, -.11), (.215, -.099),
                (.246, -.187), (.472, -.216), (.491, -.18)], .008,
                geo.material('Honed blade silver', (.63, .69, .73), .88, .24))
    for side in (-1, 1):
        geo.box('Blade reinforcement', (side * .026, .286, -.016),
                (.013, .132, .039), geo.STEEL, .004, angle=-10)
        for y in (.238, .302):
            geo.tube('Tang rivet', (side * .035, y, -.014), .007, .006,
                     geo.TAN, axis='x')
    geo.box('Hazard mark', (.026, .407, -.022), (.008, .035, .051), geo.TAN, .002)


def export(kind, build):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    geo.ROOT = bpy.data.objects.new(kind, None)
    bpy.context.collection.objects.link(geo.ROOT)
    build()
    batches = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type == 'MESH':
            batches.setdefault(obj.data.materials[0].name, []).append(obj)
    for name, objects in batches.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        objects[0].name = 'Parts_' + name
    for name, point in [('GripPivot', (0, 0, 0)), ('StrikeTip', TIPS[kind])]:
        marker = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(marker)
        marker.parent = geo.ROOT
        marker.location = geo.xyz(point)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT / (kind + '.glb')),
                              export_format='GLB', use_selection=True,
                              export_apply=True)
    print('MELEE BUILT', kind, 'tip', TIPS[kind], 'material batches', len(batches))


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, build in [('baton', baton), ('cleaver', cleaver)]:
        export(kind, build)
