import bpy
import bmesh
import math
import os

os.makedirs("assets/models", exist_ok=True)

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def make_material(name, rgba, metallic=0.1, roughness=0.5, emission=None):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission
            bsdf.inputs["Emission Strength"].default_value = 1.5
    return mat

def add_box(name, size, loc, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat:
        obj.data.materials.append(mat)
    return obj

def add_cylinder(name, radius, depth, loc, rot=(0, 0, 0), vertices=24, mat=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    return obj

# ==============================================================================
# 1. CAR COCKPIT & BODY (car_cockpit.glb)
# ==============================================================================
print("[Blender 5.2] Generating car_cockpit.glb...")
clear_scene()

mat_dash = make_material("DashboardDark", (0.11, 0.12, 0.14, 1.0), metallic=0.05, roughness=0.75)
mat_trim = make_material("SilverTrim", (0.65, 0.68, 0.72, 1.0), metallic=0.7, roughness=0.3)
mat_body = make_material("AutoEcoleWhite", (0.92, 0.94, 0.96, 1.0), metallic=0.3, roughness=0.25)
mat_red_stripe = make_material("AutoEcoleRed", (0.82, 0.12, 0.15, 1.0), metallic=0.2, roughness=0.3)
mat_seat = make_material("SeatFabric", (0.18, 0.20, 0.24, 1.0), metallic=0.0, roughness=0.9)
mat_Cluster = make_material("ClusterBack", (0.03, 0.04, 0.06, 1.0), metallic=0.1, roughness=0.2)

# Car floor & lower chassis
add_box("Floor", (1.75, 2.8, 0.08), (0.0, 0.0, 0.22), mat=mat_dash)
# Front Hood (Capot visible in 1st person view to judge distances & garage/trottoir!)
add_box("FrontHood", (1.62, 1.15, 0.12), (0.0, -1.25, 0.78), rot=(math.radians(-6), 0, 0), mat=mat_body)
add_box("HoodStripeLeft", (0.12, 1.12, 0.13), (-0.52, -1.25, 0.785), rot=(math.radians(-6), 0, 0), mat=mat_red_stripe)
add_box("HoodStripeRight", (0.12, 1.12, 0.13), (0.52, -1.25, 0.785), rot=(math.radians(-6), 0, 0), mat=mat_red_stripe)

# Dashboard main block
add_box("DashboardMain", (1.66, 0.48, 0.36), (0.0, -0.58, 0.74), mat=mat_dash)
add_box("DashboardTopVisor", (0.46, 0.28, 0.14), (-0.36, -0.52, 0.94), mat=mat_dash)
add_box("InstrumentCluster", (0.38, 0.04, 0.16), (-0.36, -0.40, 0.91), rot=(math.radians(12), 0, 0), mat=mat_Cluster)
add_box("CenterConsole", (0.30, 0.85, 0.34), (0.0, -0.22, 0.44), mat=mat_dash)
add_box("CenterScreenBezel", (0.28, 0.06, 0.18), (0.0, -0.36, 0.88), mat=mat_trim)

# Left and Right A-Pillars & Roof Frame
add_box("APillarLeft", (0.07, 0.09, 0.72), (-0.80, -0.52, 1.18), rot=(math.radians(-28), 0, math.radians(-8)), mat=mat_dash)
add_box("APillarRight", (0.07, 0.09, 0.72), (0.80, -0.52, 1.18), rot=(math.radians(-28), 0, math.radians(8)), mat=mat_dash)
add_box("RoofHeader", (1.68, 0.45, 0.06), (0.0, -0.15, 1.48), mat=mat_dash)

# Doors Left & Right
add_box("DoorLeft", (0.08, 1.35, 0.62), (-0.84, -0.05, 0.56), mat=mat_dash)
add_box("DoorRight", (0.08, 1.35, 0.62), (0.84, -0.05, 0.56), mat=mat_dash)

# Exterior Side Mirror Housings (Left & Right)
add_box("MirrorHousingLeft", (0.24, 0.10, 0.14), (-0.96, -0.48, 0.94), rot=(0, 0, math.radians(12)), mat=mat_body)
add_box("MirrorHousingRight", (0.24, 0.10, 0.14), (0.96, -0.48, 0.94), rot=(0, 0, math.radians(-12)), mat=mat_body)
# Interior Rear-View Mirror Mount
add_box("CenterMirrorHousing", (0.34, 0.05, 0.10), (0.0, -0.32, 1.36), mat=mat_dash)

# Seats (Driver & Monitor/Instructor Seat on the Right)
add_box("SeatPassengerBase", (0.48, 0.50, 0.14), (0.38, 0.18, 0.42), mat=mat_seat)
add_box("SeatPassengerBack", (0.46, 0.12, 0.62), (0.38, 0.40, 0.76), rot=(math.radians(-10), 0, 0), mat=mat_seat)

bpy.ops.export_scene.gltf(filepath="assets/models/car_cockpit.glb", export_format="GLB")

# ==============================================================================
# 2. STEERING WHEEL (steering_wheel.glb)
# ==============================================================================
print("[Blender 5.2] Generating steering_wheel.glb...")
clear_scene()
mat_wheel = make_material("WheelLeather", (0.09, 0.09, 0.11, 1.0), metallic=0.1, roughness=0.4)
mat_marker = make_material("TopMarkerRed", (0.95, 0.15, 0.15, 1.0), metallic=0.1, roughness=0.3)
mat_hub = make_material("WheelHub", (0.16, 0.17, 0.20, 1.0), metallic=0.3, roughness=0.4)

bpy.ops.mesh.primitive_torus_add(major_radius=0.18, minor_radius=0.022, major_segments=36, minor_segments=14, location=(0, 0, 0))
torus = bpy.context.active_object
torus.name = "WheelRim"
torus.data.materials.append(mat_wheel)

# 12 o'clock red marker so learner clearly tracks 1/4 turn, 1/2 turn, full turn!
add_box("TopMarker", (0.035, 0.048, 0.048), (0, 0.18, 0), mat=mat_marker)
add_cylinder("CenterHub", 0.065, 0.05, (0, 0, 0), vertices=20, mat=mat_hub)
add_box("SpokeLeft", (0.12, 0.028, 0.022), (-0.10, -0.02, 0), rot=(0, 0, math.radians(15)), mat=mat_hub)
add_box("SpokeRight", (0.12, 0.028, 0.022), (0.10, -0.02, 0), rot=(0, 0, math.radians(-15)), mat=mat_hub)
add_box("SpokeBottom", (0.032, 0.11, 0.022), (0, -0.10, 0), mat=mat_hub)

bpy.ops.export_scene.gltf(filepath="assets/models/steering_wheel.glb", export_format="GLB")

# ==============================================================================
# 3. AUTOROUTE DU MAROC TOLL ARCH (peage_autoroute.glb)
# ==============================================================================
print("[Blender 5.2] Generating peage_autoroute.glb...")
clear_scene()
mat_adm_blue = make_material("ADMBlue", (0.06, 0.28, 0.68, 1.0), metallic=0.2, roughness=0.4)
mat_adm_white = make_material("ADMWhite", (0.95, 0.95, 0.97, 1.0), metallic=0.1, roughness=0.5)
mat_adm_yellow = make_material("JawazYellow", (0.95, 0.76, 0.08, 1.0), metallic=0.2, roughness=0.3)

# Canopy & Pillars spanning across the 18m highway
add_box("CanopyRoof", (22.0, 4.5, 1.2), (0, 0, 6.2), mat=mat_adm_blue)
add_box("CanopyStripe", (22.2, 4.6, 0.35), (0, 0, 6.6), mat=mat_adm_yellow)
for px in [-9.5, -3.5, 3.5, 9.5]:
    add_box(f"Pillar_{px}", (0.9, 2.8, 6.0), (px, 0, 3.0), mat=mat_adm_white)
    add_box(f"Booth_{px}", (1.4, 2.2, 2.6), (px + 0.8, 0, 1.3), mat=mat_adm_blue)

bpy.ops.export_scene.gltf(filepath="assets/models/peage_autoroute.glb", export_format="GLB")

# ==============================================================================
# 4. MOROCCAN PALM TREE & ROUNDABOUT MONUMENT (morocco_props.glb)
# ==============================================================================
print("[Blender 5.2] Generating palm_tree.glb & rond_point_monument.glb...")
clear_scene()
mat_trunk = make_material("PalmTrunk", (0.42, 0.28, 0.16, 1.0), roughness=0.9)
mat_leaf = make_material("PalmLeaf", (0.14, 0.52, 0.20, 1.0), roughness=0.6)
add_cylinder("Trunk", 0.28, 6.5, (0, 0, 3.25), vertices=10, mat=mat_trunk)
for angle_deg in range(0, 360, 45):
    rad = math.radians(angle_deg)
    lx = math.cos(rad) * 1.4
    ly = math.sin(rad) * 1.4
    add_box(f"Frond_{angle_deg}", (2.4, 0.45, 0.12), (lx, ly, 6.3), rot=(0, math.radians(22), rad), mat=mat_leaf)
bpy.ops.export_scene.gltf(filepath="assets/models/palm_tree.glb", export_format="GLB")

clear_scene()
mat_terracotta = make_material("Terracotta", (0.82, 0.42, 0.26, 1.0), roughness=0.6)
mat_zellige = make_material("ZelligeTeal", (0.08, 0.58, 0.52, 1.0), roughness=0.3)
add_cylinder("RoundaboutBase", 5.5, 0.45, (0, 0, 0.225), vertices=32, mat=mat_terracotta)
add_cylinder("RoundaboutRing", 4.2, 0.65, (0, 0, 0.45), vertices=24, mat=mat_zellige)
add_box("MoroccanArch1", (2.8, 0.6, 3.8), (0, 0, 2.2), mat=mat_terracotta)
add_box("MoroccanArch2", (0.6, 2.8, 3.8), (0, 0, 2.2), mat=mat_terracotta)
add_box("CrownTop", (1.8, 1.8, 0.8), (0, 0, 4.3), rot=(0, 0, math.radians(45)), mat=mat_zellige)
bpy.ops.export_scene.gltf(filepath="assets/models/rond_point_monument.glb", export_format="GLB")

print("=== [25% OK] All Blender 5.2 3D GLB models exported successfully! ===")
