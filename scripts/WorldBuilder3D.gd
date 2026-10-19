class_name WorldBuilder3D
extends RefCounted

static func make_std_mat(color: Color, roughness: float = 0.7, metallic: float = 0.05, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m

static func load_glb_or_fallback(res_path: String) -> Node3D:
	if ResourceLoader.exists(res_path):
		var packed = load(res_path)
		if packed and packed is PackedScene:
			return packed.instantiate()
	return null

static func build_cockpit_node() -> Dictionary:
	var root = Node3D.new()
	root.name = "PlayerCar3D"

	# 1. Load Blender 5.2 car_cockpit.glb
	var cockpit_glb = load_glb_or_fallback("res://assets/models/car_cockpit.glb")
	if cockpit_glb:
		cockpit_glb.name = "BlenderCockpit"
		# Blender uses +Z up and -Y forward; rotate so it matches Godot (+Y up, -Z forward)
		cockpit_glb.rotation_degrees = Vector3(90, 0, 0)
		root.add_child(cockpit_glb)

	# Also add clean interior cockpit framing in Godot space so driver POV is super crisp
	var dash_mat = make_std_mat(Color(0.11, 0.12, 0.15), 0.75, 0.1)
	var hood_mat = make_std_mat(Color(0.92, 0.94, 0.97), 0.3, 0.3)
	var stripe_mat = make_std_mat(Color(0.85, 0.14, 0.16), 0.3, 0.2)

	var hood = MeshInstance3D.new()
	var hood_box = BoxMesh.new()
	hood_box.size = Vector3(1.64, 0.08, 1.35)
	hood.mesh = hood_box
	hood.material_override = hood_mat
	hood.position = Vector3(0.0, 0.76, -1.42)
	hood.rotation_degrees = Vector3(5.0, 0.0, 0.0)
	root.add_child(hood)

	# Auto-Ecole red stripes on hood (excellent visual reference for lane positioning & curb alignment!)
	for sx in [-0.52, 0.52]:
		var st = MeshInstance3D.new()
		var st_box = BoxMesh.new()
		st_box.size = Vector3(0.09, 0.09, 1.32)
		st.mesh = st_box
		st.material_override = stripe_mat
		st.position = Vector3(sx, 0.77, -1.42)
		st.rotation_degrees = Vector3(5.0, 0.0, 0.0)
		root.add_child(st)

	var dash = MeshInstance3D.new()
	var dash_box = BoxMesh.new()
	dash_box.size = Vector3(1.68, 0.38, 0.48)
	dash.mesh = dash_box
	dash.material_override = dash_mat
	dash.position = Vector3(0.0, 0.72, -0.66)
	root.add_child(dash)

	# Left & Right A-Pillars
	for px in [-0.82, 0.82]:
		var pillar = MeshInstance3D.new()
		var p_box = BoxMesh.new()
		p_box.size = Vector3(0.07, 0.75, 0.09)
		pillar.mesh = p_box
		pillar.material_override = dash_mat
		pillar.position = Vector3(px, 1.18, -0.58)
		pillar.rotation_degrees = Vector3(26.0, 0.0, -7.0 if px < 0 else 7.0)
		root.add_child(pillar)

	# 2. 3D Steering Wheel (Guidon) with 12h red marker
	var wheel_pivot = Node3D.new()
	wheel_pivot.name = "SteeringWheelPivot"
	wheel_pivot.position = Vector3(-0.36, 0.90, -0.42)
	wheel_pivot.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	root.add_child(wheel_pivot)

	var wheel_holder = Node3D.new()
	wheel_holder.name = "WheelSpinner"
	wheel_pivot.add_child(wheel_holder)

	var wheel_glb = load_glb_or_fallback("res://assets/models/steering_wheel.glb")
	if wheel_glb:
		wheel_holder.add_child(wheel_glb)
	else:
		var torus_mi = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 0.155
		torus.outer_radius = 0.195
		torus_mi.mesh = torus
		torus_mi.rotation_degrees = Vector3(90, 0, 0)
		torus_mi.material_override = make_std_mat(Color(0.08, 0.09, 0.11), 0.4, 0.2)
		wheel_holder.add_child(torus_mi)

	# Add an extra bright 12-o'clock red marker on the 3D steering wheel rim
	var top_mark = MeshInstance3D.new()
	var tm_box = BoxMesh.new()
	tm_box.size = Vector3(0.038, 0.045, 0.045)
	top_mark.mesh = tm_box
	top_mark.position = Vector3(0.0, 0.18, 0.0)
	top_mark.material_override = make_std_mat(Color(0.98, 0.15, 0.15), 0.2, 0.1, 0.6)
	wheel_holder.add_child(top_mark)

	# 3. 3D Foot Pedals (Left = Embrayage Blue/Green, Middle = Frein Red, Right = Accélérateur Yellow)
	var pedals_root = Node3D.new()
	pedals_root.position = Vector3(-0.36, 0.36, -0.58)
	root.add_child(pedals_root)

	var pedal_clutch = MeshInstance3D.new()
	var pc_box = BoxMesh.new()
	pc_box.size = Vector3(0.065, 0.12, 0.03)
	pedal_clutch.mesh = pc_box
	pedal_clutch.position = Vector3(-0.13, 0.0, 0.0)
	pedal_clutch.material_override = make_std_mat(Color(0.15, 0.65, 0.95), 0.4, 0.2, 0.3)
	pedals_root.add_child(pedal_clutch)

	var pedal_brake = MeshInstance3D.new()
	pedal_brake.mesh = pc_box
	pedal_brake.position = Vector3(0.0, 0.0, 0.0)
	pedal_brake.material_override = make_std_mat(Color(0.92, 0.22, 0.22), 0.4, 0.2, 0.3)
	pedals_root.add_child(pedal_brake)

	var pedal_gas = MeshInstance3D.new()
	pedal_gas.mesh = pc_box
	pedal_gas.position = Vector3(0.13, 0.0, 0.0)
	pedal_gas.material_override = make_std_mat(Color(0.20, 0.85, 0.38), 0.4, 0.2, 0.3)
	pedals_root.add_child(pedal_gas)

	# 4. 3D Gear Stick (Levier de vitesse)
	var gear_stick = Node3D.new()
	gear_stick.position = Vector3(0.0, 0.62, -0.34)
	root.add_child(gear_stick)

	var stick_rod = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.016
	cyl.height = 0.20
	stick_rod.mesh = cyl
	stick_rod.position = Vector3(0.0, 0.10, 0.0)
	stick_rod.material_override = make_std_mat(Color(0.7, 0.72, 0.75), 0.3, 0.8)
	gear_stick.add_child(stick_rod)

	var knob = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = 0.034
	sph.height = 0.068
	knob.mesh = sph
	knob.position = Vector3(0.0, 0.20, 0.0)
	knob.material_override = make_std_mat(Color(0.15, 0.16, 0.18), 0.3, 0.4)
	gear_stick.add_child(knob)

	# 5. Headlights (SpotLight3D for الفيوز / الكود / الفار)
	var headlights = Node3D.new()
	headlights.name = "Headlights"
	root.add_child(headlights)
	var left_light = SpotLight3D.new()
	left_light.position = Vector3(-0.62, 0.72, -2.05)
	left_light.spot_range = 35.0
	left_light.spot_angle = 32.0
	left_light.light_energy = 1.5
	left_light.light_color = Color(1.0, 0.97, 0.88)
	headlights.add_child(left_light)

	var right_light = SpotLight3D.new()
	right_light.position = Vector3(0.62, 0.72, -2.05)
	right_light.spot_range = 35.0
	right_light.spot_angle = 32.0
	right_light.light_energy = 1.5
	right_light.light_color = Color(1.0, 0.97, 0.88)
	headlights.add_child(right_light)

	# 6. First-person Driver Camera
	var driver_cam = Camera3D.new()
	driver_cam.name = "DriverCamera3D"
	driver_cam.position = Vector3(-0.36, 1.18, -0.02)
	driver_cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	driver_cam.fov = 68.0
	driver_cam.current = true
	root.add_child(driver_cam)

	return {
		"root": root,
		"wheel_spinner": wheel_holder,
		"pedal_clutch": pedal_clutch,
		"pedal_brake": pedal_brake,
		"pedal_gas": pedal_gas,
		"gear_stick": gear_stick,
		"left_light": left_light,
		"right_light": right_light,
		"driver_cam": driver_cam
	}

static func build_morocco_world(world_root: Node3D, mode_id: String) -> Dictionary:
	# Clear old children if any
	for c in world_root.get_children():
		c.queue_free()

	var pts = MoroccoData.get_osm_route_points(mode_id)
	var is_highway = (mode_id == "autoroute_a1")
	var road_width = 16.0 if is_highway else 10.5

	# Ground plane (Moroccan coastal / urban terrain)
	var ground = MeshInstance3D.new()
	var g_plane = PlaneMesh.new()
	g_plane.size = Vector2(1200.0, 3600.0)
	ground.mesh = g_plane
	ground.position = Vector3(0.0, -0.08, -1200.0)
	var g_color = Color(0.76, 0.68, 0.52) if is_highway else Color(0.32, 0.36, 0.34)
	ground.material_override = make_std_mat(g_color, 0.95, 0.0)
	world_root.add_child(ground)

	var mat_asphalt = make_std_mat(Color(0.18, 0.19, 0.22), 0.85, 0.05)
	var mat_line_white = make_std_mat(Color(0.95, 0.95, 0.95), 0.4, 0.0, 0.25)
	var mat_curb_red = make_std_mat(Color(0.85, 0.15, 0.15), 0.6, 0.0)
	var mat_curb_white = make_std_mat(Color(0.95, 0.95, 0.95), 0.6, 0.0)
	var mat_sign_blue = make_std_mat(Color(0.06, 0.32, 0.75), 0.4, 0.1, 0.2)
	var mat_sign_green = make_std_mat(Color(0.08, 0.52, 0.24), 0.4, 0.1, 0.2)

	var palm_packed = load("res://assets/models/palm_tree.glb") if ResourceLoader.exists("res://assets/models/palm_tree.glb") else null
	var peage_packed = load("res://assets/models/peage_autoroute.glb") if ResourceLoader.exists("res://assets/models/peage_autoroute.glb") else null
	var rp_packed = load("res://assets/models/rond_point_monument.glb") if ResourceLoader.exists("res://assets/models/rond_point_monument.glb") else null

	var peage_z: float = -99999.0
	var roundabouts: Array = []
	var traffic_cars: Array = []

	for i in range(pts.size() - 1):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var mid: Vector3 = (p1 + p2) * 0.5
		var diff: Vector3 = p2 - p1
		var seg_len: float = diff.length()
		var yaw: float = atan2(-diff.x, -diff.z)
		var pitch: float = atan2(diff.y, Vector2(diff.x, diff.z).length())

		# Road segment mesh
		var seg = MeshInstance3D.new()
		var r_box = BoxMesh.new()
		r_box.size = Vector3(road_width, 0.12, seg_len + 1.2)
		seg.mesh = r_box
		seg.material_override = mat_asphalt
		seg.position = mid
		seg.rotation = Vector3(pitch, yaw, 0.0)
		world_root.add_child(seg)

		# Center & Lane markings
		var dash = MeshInstance3D.new()
		var d_box = BoxMesh.new()
		d_box.size = Vector3(0.18, 0.14, seg_len * 0.45)
		dash.mesh = d_box
		dash.material_override = mat_line_white
		dash.position = mid + Vector3(0, 0.02, 0)
		dash.rotation = Vector3(pitch, yaw, 0.0)
		world_root.add_child(dash)

		# Moroccan Red & White Curbs (طروطوار بالأحمر والأبيض)
		for side in [-1.0, 1.0]:
			var curb = MeshInstance3D.new()
			var c_box = BoxMesh.new()
			c_box.size = Vector3(0.45, 0.26, seg_len + 0.5)
			curb.mesh = c_box
			curb.material_override = mat_curb_red if (i % 2 == 0) else mat_curb_white
			var right_vec = Vector3(cos(yaw), 0, -sin(yaw))
			curb.position = mid + right_vec * (side * (road_width * 0.5 + 0.25)) + Vector3(0, 0.08, 0)
			curb.rotation = Vector3(pitch, yaw, 0.0)
			world_root.add_child(curb)

		# Place Palm Trees & Moroccan Buildings along the road
		if i % 2 == 0 and palm_packed:
			for side in [-1.0, 1.0]:
				var palm = palm_packed.instantiate()
				palm.rotation_degrees = Vector3(90, 0, 0)
				var right_vec = Vector3(cos(yaw), 0, -sin(yaw))
				palm.position = mid + right_vec * (side * (road_width * 0.5 + 3.8))
				world_root.add_child(palm)

		if not is_highway and i % 3 == 1:
			for side in [-1.0, 1.0]:
				var bld = MeshInstance3D.new()
				var b_box = BoxMesh.new()
				var bh = 8.0 + float((i * 7) % 14)
				b_box.size = Vector3(9.0, bh, 12.0)
				bld.mesh = b_box
				var b_col = Color(0.93, 0.91, 0.87) if mode_id == "casa_urbain" else Color(0.88, 0.78, 0.66)
				bld.material_override = make_std_mat(b_col, 0.8, 0.05)
				var right_vec = Vector3(cos(yaw), 0, -sin(yaw))
				bld.position = mid + right_vec * (side * (road_width * 0.5 + 10.5)) + Vector3(0, bh * 0.5, 0)
				bld.rotation = Vector3(0, yaw, 0)
				world_root.add_child(bld)

		# Place Roundabouts (الدوار / الرومبوان) in Urban & Circuit modes
		if (not is_highway) and (i == 10 or i == 25 or i == 38):
			roundabouts.append(mid)
			if rp_packed:
				var rp = rp_packed.instantiate()
				rp.rotation_degrees = Vector3(90, 0, 0)
				rp.scale = Vector3(0.42, 0.42, 0.42)
				rp.position = mid + Vector3(0, 0.05, 0)
				world_root.add_child(rp)
			_add_road_sign_3d(world_root, mid + Vector3(road_width * 0.5 + 1.8, 0.0, 14.0), "🔄 مدار ROND-POINT\nالأسبقية لليسار (2ème)", mat_sign_green)

		# Place Autoroute A1 Overhead Signs & Péage Bouznika
		if is_highway:
			if i == 3:
				_add_road_sign_3d(world_root, mid + Vector3(road_width * 0.5 + 2.2, 0.0, 0.0), "🛣️ A1 الرباط RABAT 95 km\nالمحمدية MOHAMMEDIA 22 km\nالسرعة 120 km/h", mat_sign_blue)
			elif i == 15:
				_add_road_sign_3d(world_root, mid + Vector3(road_width * 0.5 + 2.2, 0.0, 0.0), "🛣️ بوزنيقة BOUZNIKA\nمحطة الأداء PÉAGE 500m\nنقص السرعة 80 km/h", mat_sign_blue)
			elif i == 26:
				_add_road_sign_3d(world_root, mid + Vector3(road_width * 0.5 + 2.2, 0.0, 0.0), "🛑 محطة الأداء PÉAGE\nورك على اللومبرياج + الفران\nجواز JAWAZ", mat_sign_blue)
			elif i == 30 and peage_packed:
				var peage = peage_packed.instantiate()
				peage.rotation_degrees = Vector3(90, 0, 0)
				peage.position = mid
				world_root.add_child(peage)
				peage_z = mid.z
			elif i == 42:
				_add_road_sign_3d(world_root, mid + Vector3(road_width * 0.5 + 2.2, 0.0, 0.0), "🛣️ الصخيرات SKHIRAT\nتمارة TEMARA - الرباط RABAT\n120 km/h", mat_sign_blue)
			elif i == 55:
				_add_road_sign_3d(world_root, mid + Vector3(road_width * 0.5 + 2.2, 0.0, 0.0), "🏛️ مرحبا بكم في الرباط\nBIENVENUE À RABAT\nشارع محمد الخامس - 60 km/h", mat_sign_green)

	# Add slope sign for circuit_permis
	if mode_id == "circuit_permis":
		_add_road_sign_3d(world_root, pts[9] + Vector3(6.5, 0.0, 0.0), "⛰️ العقبة (Démarrage en côte)\nوقف وعاود قلع باللومبرياج والفران د اليد", mat_sign_blue)
		_add_road_sign_3d(world_root, pts[2] + Vector3(6.5, 0.0, 0.0), "🅿️ منطقة التدريب: 1ère + Patinage\nهز اللومبرياج بشوية (45%-65%)", mat_sign_green)

	# Spawn AI Traffic Cars (so player sees cars ahead and behind in the 3 Rear-View Mirrors!)
	var taxi_colors = [
		Color(0.88, 0.14, 0.16), # Petit Taxi Casablanca (Red)
		Color(0.12, 0.48, 0.88), # Petit Taxi Rabat (Blue)
		Color(0.94, 0.94, 0.92), # Grand Taxi Maroc (White)
		Color(0.22, 0.25, 0.30)
	]
	for ti in range(8):
		var t_car = _create_traffic_car_mesh(taxi_colors[ti % taxi_colors.size()])
		var pt_idx = clampi(3 + ti * 6, 1, pts.size() - 2)
		var lane_off = 2.6 if (ti % 2 == 0) else -2.6
		t_car.position = pts[pt_idx] + Vector3(lane_off, 0.0, 0.0)
		world_root.add_child(t_car)
		traffic_cars.append({
			"node": t_car,
			"pt_idx": float(pt_idx),
			"lane_offset": lane_off,
			"speed_mps": (16.0 if is_highway else 9.5) * (1.0 if ti % 2 == 0 else 0.85)
		})

	return {
		"points": pts,
		"peage_z": peage_z,
		"roundabouts": roundabouts,
		"traffic_cars": traffic_cars,
		"road_width": road_width
	}

static func _add_road_sign_3d(parent: Node3D, pos: Vector3, text: String, board_mat: StandardMaterial3D) -> void:
	var sign_root = Node3D.new()
	sign_root.position = pos
	parent.add_child(sign_root)

	var pole = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = 3.6
	pole.mesh = cyl
	pole.position = Vector3(0, 1.8, 0)
	pole.material_override = make_std_mat(Color(0.65, 0.68, 0.72), 0.4, 0.6)
	sign_root.add_child(pole)

	var board = MeshInstance3D.new()
	var b_box = BoxMesh.new()
	b_box.size = Vector3(3.6, 1.45, 0.12)
	board.mesh = b_box
	board.position = Vector3(-0.8, 3.4, 0)
	board.material_override = board_mat
	sign_root.add_child(board)

	var lbl = Label3D.new()
	lbl.text = text
	lbl.font_size = 38
	lbl.outline_size = 8
	lbl.modulate = Color(1, 1, 1)
	lbl.position = Vector3(-0.8, 3.4, 0.08)
	sign_root.add_child(lbl)

static func _create_traffic_car_mesh(col: Color) -> Node3D:
	var root = Node3D.new()
	var body = MeshInstance3D.new()
	var b_box = BoxMesh.new()
	b_box.size = Vector3(1.76, 0.72, 3.9)
	body.mesh = b_box
	body.position = Vector3(0, 0.52, 0)
	body.material_override = make_std_mat(col, 0.35, 0.25)
	root.add_child(body)

	var cabin = MeshInstance3D.new()
	var c_box = BoxMesh.new()
	c_box.size = Vector3(1.52, 0.56, 2.0)
	cabin.mesh = c_box
	cabin.position = Vector3(0, 1.12, 0.15)
	cabin.material_override = make_std_mat(Color(0.15, 0.18, 0.24), 0.2, 0.4)
	root.add_child(cabin)

	# Tail lights & Headlights so they are clearly visible in mirrors & night mode!
	var tail = MeshInstance3D.new()
	var t_box = BoxMesh.new()
	t_box.size = Vector3(1.5, 0.16, 0.08)
	tail.mesh = t_box
	tail.position = Vector3(0, 0.65, 1.96)
	tail.material_override = make_std_mat(Color(1.0, 0.1, 0.1), 0.2, 0.0, 2.2)
	root.add_child(tail)

	return root
