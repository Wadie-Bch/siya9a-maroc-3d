extends Node3D

var sim: CarSimulator = CarSimulator.new()
var world_root: Node3D
var car_nodes: Dictionary = {}
var route_info: Dictionary = {}
var current_mode_id: String = "circuit_permis"

# Mirror cameras
var cam_mirror_center: Camera3D
var cam_mirror_left: Camera3D
var cam_mirror_right: Camera3D
var head_yaw_target: float = 0.0

# Environment
var world_env: WorldEnvironment
var sun_light: DirectionalLight3D

# UI References
var ui_root: Control
var lobby_panel: PanelContainer
var why_modal: PanelContainer
var why_text_label: RichTextLabel
var clutch_plate_motor: ColorRect
var clutch_plate_disc: ColorRect
var clutch_status_lbl: Label
var clutch_slider: VSlider
var clutch_pct_label: Label
var speed_label: Label
var rpm_label: Label
var gear_badge_label: Label
var turn_state_label: Label
var monitor_banner: PanelContainer
var monitor_label: Label
var light_btn: Button
var handbrake_btn: Button
var engine_btn: Button
var blinker_left_btn: Button
var blinker_right_btn: Button
var hazard_btn: Button
var gear_buttons: Dictionary = {}
var is_dragging_wheel: bool = false
var drag_start_x: float = 0.0
var drag_start_deg: float = 0.0
var throttle_held: bool = false
var brake_held: bool = false
var steer_left_held: bool = false
var steer_right_held: bool = false
var peage_stopped_once: bool = false
var lesson_content_lbl: RichTextLabel

func _ready() -> void:
	_setup_environment()
	world_root = Node3D.new()
	world_root.name = "MoroccoOSMWorld"
	add_child(world_root)

	car_nodes = WorldBuilder3D.build_cockpit_node()
	add_child(car_nodes["root"])

	_build_hud_and_lobby()
	_load_driving_mode("circuit_permis", true)

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.72, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.9
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	sun_light.light_energy = 1.25
	sun_light.light_color = Color(1.0, 0.97, 0.90)
	add_child(sun_light)

func _load_driving_mode(mode_id: String, show_lobby: bool = false) -> void:
	current_mode_id = mode_id
	peage_stopped_once = false
	route_info = WorldBuilder3D.build_morocco_world(world_root, mode_id)
	var pts: Array = route_info.get("points", [Vector3.ZERO])
	var start_pt: Vector3 = pts[0] + Vector3(2.4, 0.0, -4.0)
	var start_yaw: float = 0.0
	if pts.size() > 1:
		var d: Vector3 = pts[1] - pts[0]
		start_yaw = atan2(-d.x, -d.z)
	sim.reset_for_route(start_pt, start_yaw)
	if clutch_slider:
		clutch_slider.value = 100.0

	var catalog = MoroccoData.get_routes_catalog()
	var tod = "day"
	for item in catalog:
		if item["id"] == mode_id:
			tod = item["time_of_day"]
			break

	if tod == "night":
		world_env.environment.background_color = Color(0.04, 0.06, 0.12)
		world_env.environment.ambient_light_energy = 0.25
		sun_light.light_energy = 0.12
		sim.light_mode = 2
		sim.monitor_message = "🌙 السياقة الليلية فـ الرباط! شعلنا ليك ضو التقابل (الكود 30m). جرب تبدل البولات (الفيوز / الكود / الفار) وهز اللومبرياج بشوية."
	elif tod == "sunset":
		world_env.environment.background_color = Color(0.85, 0.48, 0.32)
		world_env.environment.ambient_light_energy = 0.65
		sun_light.light_energy = 0.85
		sim.monitor_message = "🛣️ مرحبا بيك فـ لوطوروت كازا ↔ الرباط (A1 - 120 كم/س)! اندمج بـ السينيال اليسار، طلع الفيتيس حتى لـ 5ème، ووقف فـ محطة الأداء بوزنيقة."
	else:
		world_env.environment.background_color = Color(0.45, 0.72, 0.96)
		world_env.environment.ambient_light_energy = 0.92
		sun_light.light_energy = 1.25

	_sync_3d_transforms(0.016)
	_update_ui_labels()
	if lobby_panel:
		lobby_panel.visible = show_lobby

func _process(delta: float) -> void:
	if lobby_panel and lobby_panel.visible:
		return

	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W) or throttle_held:
		sim.throttle_input = move_toward(sim.throttle_input, 1.0, delta * 3.2)
	else:
		sim.throttle_input = move_toward(sim.throttle_input, 0.0, delta * 4.5)

	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) or brake_held:
		sim.brake_input = move_toward(sim.brake_input, 1.0, delta * 4.2)
	else:
		sim.brake_input = move_toward(sim.brake_input, 0.0, delta * 5.5)

	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or steer_left_held:
		sim.steering_deg = clampf(sim.steering_deg - delta * 220.0, -540.0, 540.0)
	elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or steer_right_held:
		sim.steering_deg = clampf(sim.steering_deg + delta * 220.0, -540.0, 540.0)
	elif not is_dragging_wheel and abs(sim.speed_kmh) > 8.0:
		sim.steering_deg = move_toward(sim.steering_deg, 0.0, delta * abs(sim.speed_kmh) * 2.2)

	_update_road_elevation_and_events(delta)
	sim.step_physics(delta)
	_sync_3d_transforms(delta)
	_update_ui_labels()

func _update_road_elevation_and_events(delta: float) -> void:
	var pts: Array = route_info.get("points", [])
	if pts.size() >= 2:
		var best_dist = 999999.0
		var best_idx = 0
		for i in range(pts.size() - 1):
			var d = sim.pos_3d.distance_to(pts[i])
			if d < best_dist:
				best_dist = d
				best_idx = i
		var p1: Vector3 = pts[best_idx]
		var p2: Vector3 = pts[min(best_idx + 1, pts.size() - 1)]
		sim.pos_3d.y = lerpf(sim.pos_3d.y, p1.y, delta * 8.0)
		var dy = p2.y - p1.y
		var dz = maxf(1.0, Vector2(p2.x - p1.x, p2.z - p1.z).length())
		sim.current_slope_deg = rad_to_deg(atan2(dy, dz))

		var lateral_dist = abs(sim.pos_3d.x - p1.x)
		var max_off = route_info.get("road_width", 12.0) * 0.65
		if lateral_dist > max_off and abs(sim.speed_kmh) > 5.0:
			sim.monitor_status = "warn"
			sim.monitor_message = "⚠️ خرجتي على الطروطوار/المسلك! دور الفولان بشوية (ربع دورة) باش ترجع لوسط الطريق."

	var peage_z: float = route_info.get("peage_z", -99999.0)
	if current_mode_id == "autoroute_a1" and not peage_stopped_once:
		var dist_to_peage = sim.pos_3d.z - peage_z
		if dist_to_peage > 0.0 and dist_to_peage < 120.0 and sim.speed_kmh > 65.0:
			sim.monitor_status = "warn"
			sim.monitor_message = "🛑 محطة الأداء بوزنيقة (Péage) على بعد " + str(int(dist_to_peage)) + "m! نقص السرعة بالفران وكراطي الفيتيس (4 -> 3 -> 2)!"
		elif abs(dist_to_peage) < 18.0 and abs(sim.speed_kmh) < 3.0:
			peage_stopped_once = true
			sim.monitor_status = "good"
			sim.monitor_message = "✅ أداء جواز مقبول فـ محطة بوزنيقة! الباريير تحلات، دير 1ère وهز اللومبرياج لنقطة الوصل وكمل الطريق للرباط!"
			sim._record_diagnostic(
				"الوقوف الناجح فـ محطة الأداء بوزنيقة (Péage Autoroute du Maroc)",
				"برافو! نقصتي السرعة بالتدريج، وركتي على اللومبرياج 100% قبل الوقوف باش ما تسكتش الطوموبيل، ووقفتي قدام الباريير. دابا تقدر تقلع بـ 1ère وتطلع حتى لـ 5ème (120 كم/س) فـ اتجاه الصخيرات والرباط!"
			)

	var t_cars: Array = route_info.get("traffic_cars", [])
	for tc in t_cars:
		tc["pt_idx"] += (tc["speed_mps"] * delta) / 28.0
		if tc["pt_idx"] >= float(pts.size() - 2):
			tc["pt_idx"] = 1.0
		var idx_i = int(tc["pt_idx"])
		var frac = tc["pt_idx"] - float(idx_i)
		if idx_i < pts.size() - 1:
			var a: Vector3 = pts[idx_i]
			var b: Vector3 = pts[idx_i + 1]
			var diff = b - a
			var yaw = atan2(-diff.x, -diff.z)
			var right_v = Vector3(cos(yaw), 0, -sin(yaw))
			var c_node: Node3D = tc["node"]
			c_node.position = a.lerp(b, frac) + right_v * tc["lane_offset"]
			c_node.rotation = Vector3(0, yaw, 0)

func _sync_3d_transforms(delta: float) -> void:
	var car_root: Node3D = car_nodes["root"]
	car_root.position = sim.pos_3d
	car_root.rotation = Vector3(deg_to_rad(sim.current_slope_deg), sim.heading_rad, 0.0)

	var wheel_spinner: Node3D = car_nodes["wheel_spinner"]
	wheel_spinner.rotation_degrees = Vector3(0.0, 0.0, -sim.steering_deg)

	var pc: MeshInstance3D = car_nodes["pedal_clutch"]
	var pb: MeshInstance3D = car_nodes["pedal_brake"]
	var pg: MeshInstance3D = car_nodes["pedal_gas"]
	pc.position.z = -sim.clutch_input * 0.06
	pb.position.z = -sim.brake_input * 0.05
	pg.position.z = -sim.throttle_input * 0.05

	var gs: Node3D = car_nodes["gear_stick"]
	var gx = 0.0
	var gz = 0.0
	match sim.current_gear:
		1: gx = -8.0; gz = -10.0
		2: gx = -8.0; gz = 10.0
		3: gx = 0.0; gz = -10.0
		4: gx = 0.0; gz = 10.0
		5: gx = 8.0; gz = -10.0
		-1: gx = 8.0; gz = 10.0
	gs.rotation_degrees = Vector3(gz, 0.0, -gx)

	var ll: SpotLight3D = car_nodes["left_light"]
	var rl: SpotLight3D = car_nodes["right_light"]
	match sim.light_mode:
		0:
			ll.visible = false
			rl.visible = false
		1:
			ll.visible = true
			rl.visible = true
			ll.spot_range = 10.0
			rl.spot_range = 10.0
			ll.light_energy = 0.45
			rl.light_energy = 0.45
		2:
			ll.visible = true
			rl.visible = true
			ll.spot_range = 38.0
			rl.spot_range = 38.0
			ll.light_energy = 1.8
			rl.light_energy = 1.8
		3:
			ll.visible = true
			rl.visible = true
			ll.spot_range = 110.0
			rl.spot_range = 110.0
			ll.light_energy = 3.4
			rl.light_energy = 3.4

	var d_cam: Camera3D = car_nodes["driver_cam"]
	d_cam.rotation_degrees.y = lerpf(d_cam.rotation_degrees.y, head_yaw_target, delta * 10.0)

	var global_car_pos = car_root.global_position
	var back_yaw = sim.heading_rad + PI
	if cam_mirror_center:
		cam_mirror_center.global_position = global_car_pos + Vector3(0.0, 1.32, 0.0)
		cam_mirror_center.global_rotation = Vector3(deg_to_rad(-2.0), back_yaw, 0.0)
	if cam_mirror_left:
		cam_mirror_left.global_position = global_car_pos + Vector3(-0.95, 0.98, -0.35)
		cam_mirror_left.global_rotation = Vector3(deg_to_rad(-3.0), back_yaw + deg_to_rad(14.0), 0.0)
	if cam_mirror_right:
		cam_mirror_right.global_position = global_car_pos + Vector3(0.95, 0.98, -0.35)
		cam_mirror_right.global_rotation = Vector3(deg_to_rad(-3.0), back_yaw - deg_to_rad(14.0), 0.0)

func _make_stylebox(bg: Color, border: Color, radius: int = 8, border_w: int = 2) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _create_mirror_widget(title_txt: String, w: int, h: int, fov_val: float) -> Dictionary:
	var frame = PanelContainer.new()
	frame.custom_minimum_size = Vector2(w, h)
	frame.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.07, 0.09, 0.92), Color(0.55, 0.62, 0.72), 10, 2))

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	frame.add_child(vbox)

	var lbl = Label.new()
	lbl.text = title_txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))
	vbox.add_child(lbl)

	var svc = SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(w - 10, h - 22)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(svc)

	var sv = SubViewport.new()
	sv.size = Vector2i(w - 10, h - 22)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.world_3d = get_world_3d()
	svc.add_child(sv)

	var cam = Camera3D.new()
	cam.fov = fov_val
	sv.add_child(cam)

	return {"frame": frame, "camera": cam}

func _build_hud_and_lobby() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)

	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui_root)

	# =========================================================================
	# 1. TOP BAR: 3 WORKING REAR-VIEW MIRRORS + NAVIGATION & "علاش؟" BUTTON
	# =========================================================================
	var top_bar = HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 10
	top_bar.offset_right = -10
	top_bar.offset_top = 6
	top_bar.offset_bottom = 96
	top_bar.add_theme_constant_override("separation", 8)
	ui_root.add_child(top_bar)

	# Left Side Mirror (المراية اليسرى)
	var m_left = _create_mirror_widget("🪞 المراية اليسرى (Gauche)", 175, 86, 55.0)
	cam_mirror_left = m_left["camera"]
	top_bar.add_child(m_left["frame"])

	# Left quick buttons (Lobby + Look Left/Center/Right)
	var nav_col = VBoxContainer.new()
	nav_col.add_theme_constant_override("separation", 4)
	top_bar.add_child(nav_col)

	var lobby_btn = Button.new()
	lobby_btn.text = "🏠 اللوبي والدروس"
	lobby_btn.custom_minimum_size = Vector2(140, 38)
	lobby_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.12, 0.28, 0.58), Color(0.38, 0.65, 0.98), 8))
	lobby_btn.pressed.connect(func(): lobby_panel.visible = true)
	nav_col.add_child(lobby_btn)

	var look_row = HBoxContainer.new()
	look_row.add_theme_constant_override("separation", 3)
	nav_col.add_child(look_row)

	var look_l = Button.new()
	look_l.text = "👀 يسار"
	look_l.pressed.connect(func(): head_yaw_target = 32.0)
	look_row.add_child(look_l)

	var look_c = Button.new()
	look_c.text = "أمام"
	look_c.pressed.connect(func(): head_yaw_target = 0.0)
	look_row.add_child(look_c)

	var look_r = Button.new()
	look_r.text = "يمين 👀"
	look_r.pressed.connect(func(): head_yaw_target = -32.0)
	look_row.add_child(look_r)

	# Center Rear-View Mirror (المراية الوسطانية)
	var m_center = _create_mirror_widget("🪞 المراية الوسطانية (Rétroviseur Central)", 250, 86, 48.0)
	cam_mirror_center = m_center["camera"]
	top_bar.add_child(m_center["frame"])

	# Telemetry Dashboard Cluster (Speed km/h, RPM, Current Gear)
	var dash_panel = PanelContainer.new()
	dash_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dash_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.08, 0.14, 0.90), Color(0.25, 0.45, 0.72), 10))
	top_bar.add_child(dash_panel)

	var dash_hbox = HBoxContainer.new()
	dash_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dash_hbox.add_theme_constant_override("separation", 12)
	dash_panel.add_child(dash_hbox)

	var spd_vbox = VBoxContainer.new()
	spd_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dash_hbox.add_child(spd_vbox)
	speed_label = Label.new()
	speed_label.text = "0 كم/س"
	speed_label.add_theme_font_size_override("font_size", 22)
	speed_label.add_theme_color_override("font_color", Color(0.25, 0.98, 0.55))
	spd_vbox.add_child(speed_label)
	rpm_label = Label.new()
	rpm_label.text = "850 RPM"
	rpm_label.add_theme_font_size_override("font_size", 12)
	rpm_label.add_theme_color_override("font_color", Color(0.80, 0.85, 0.92))
	spd_vbox.add_child(rpm_label)

	gear_badge_label = Label.new()
	gear_badge_label.text = "N"
	gear_badge_label.add_theme_font_size_override("font_size", 28)
	gear_badge_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	dash_hbox.add_child(gear_badge_label)

	# Interactive "❓ علاش؟ / شرح ليا" Button!
	var why_btn = Button.new()
	why_btn.text = "❓ علاش؟\nشرح ليا دابا!"
	why_btn.custom_minimum_size = Vector2(130, 76)
	why_btn.add_theme_font_size_override("font_size", 14)
	why_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.75, 0.18, 0.12), Color(1.0, 0.78, 0.22), 10, 2))
	why_btn.pressed.connect(_open_why_modal)
	top_bar.add_child(why_btn)

	# Right Side Mirror (المراية اليمنى)
	var m_right = _create_mirror_widget("🪞 المراية اليمنى (Droite)", 175, 86, 55.0)
	cam_mirror_right = m_right["camera"]
	top_bar.add_child(m_right["frame"])

	# =========================================================================
	# 2. SMART MONITOR BANNER (المونيتور السي محمد)
	# =========================================================================
	monitor_banner = PanelContainer.new()
	monitor_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	monitor_banner.offset_left = 195
	monitor_banner.offset_right = -195
	monitor_banner.offset_top = 98
	monitor_banner.offset_bottom = 142
	monitor_banner.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.14, 0.24, 0.88), Color(0.25, 0.75, 0.98), 8))
	ui_root.add_child(monitor_banner)

	monitor_label = Label.new()
	monitor_label.text = sim.monitor_message
	monitor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	monitor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	monitor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	monitor_label.add_theme_font_size_override("font_size", 13)
	monitor_banner.add_child(monitor_label)

	# =========================================================================
	# 3. BOTTOM LEFT: EMBRAYAGE IN LEFT + STEERING WHEEL (GUIDON)
	# =========================================================================
	var left_cluster = HBoxContainer.new()
	left_cluster.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left_cluster.offset_left = 10
	left_cluster.offset_bottom = -8
	left_cluster.offset_top = -315
	left_cluster.offset_right = 560
	left_cluster.add_theme_constant_override("separation", 10)
	ui_root.add_child(left_cluster)

	# A) EMBRAYAGE PEDAL BOX ON THE FAR LEFT (اللومبرياج فـ اليسار)
	var clutch_card = PanelContainer.new()
	clutch_card.custom_minimum_size = Vector2(145, 300)
	clutch_card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.09, 0.16, 0.90), Color(0.20, 0.68, 0.98), 12))
	left_cluster.add_child(clutch_card)

	var clutch_vbox = VBoxContainer.new()
	clutch_vbox.add_theme_constant_override("separation", 4)
	clutch_card.add_child(clutch_vbox)

	var c_title = Label.new()
	c_title.text = "🦶 اللومبرياج\n(Embrayage)"
	c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_title.add_theme_font_size_override("font_size", 13)
	c_title.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	clutch_vbox.add_child(c_title)

	var slider_row = HBoxContainer.new()
	slider_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slider_row.alignment = BoxContainer.ALIGNMENT_CENTER
	clutch_vbox.add_child(slider_row)

	# Visual Zone Legend next to slider (0% Released -> 45-65% Patinage -> 100% Pressed)
	var zone_col = VBoxContainer.new()
	zone_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slider_row.add_child(zone_col)

	var z_top = Label.new()
	z_top.text = "100% موروك\n(بدل الفيتيس)"
	z_top.add_theme_font_size_override("font_size", 10)
	z_top.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	zone_col.add_child(z_top)

	var pat_box = PanelContainer.new()
	pat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pat_box.add_theme_stylebox_override("panel", _make_stylebox(Color(0.08, 0.48, 0.22, 0.75), Color(0.25, 0.95, 0.45), 6, 1))
	zone_col.add_child(pat_box)
	var z_mid = Label.new()
	z_mid.text = "🟢 نقطة الوصل\nPatinage\n40% - 65%"
	z_mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	z_mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	z_mid.add_theme_font_size_override("font_size", 10)
	pat_box.add_child(z_mid)

	var z_bot = Label.new()
	z_bot.text = "0% مطلوق\n(شابك)"
	z_bot.add_theme_font_size_override("font_size", 10)
	z_bot.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	zone_col.add_child(z_bot)

	clutch_slider = VSlider.new()
	clutch_slider.min_value = 0.0
	clutch_slider.max_value = 100.0
	clutch_slider.step = 1.0
	clutch_slider.value = 100.0
	clutch_slider.custom_minimum_size = Vector2(44, 175)
	clutch_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clutch_slider.value_changed.connect(func(val: float):
		sim.clutch_input = val / 100.0
	)
	slider_row.add_child(clutch_slider)

	clutch_pct_label = Label.new()
	clutch_pct_label.text = "100% (موروك)"
	clutch_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clutch_pct_label.add_theme_font_size_override("font_size", 12)
	clutch_vbox.add_child(clutch_pct_label)

	# Quick helper buttons for clutch (100% press / 52% Patinage / Smooth release)
	var c_quick = HBoxContainer.new()
	c_quick.alignment = BoxContainer.ALIGNMENT_CENTER
	clutch_vbox.add_child(c_quick)

	var btn_c100 = Button.new()
	btn_c100.text = "100%"
	btn_c100.pressed.connect(func():
		clutch_slider.value = 100.0
		sim.clutch_input = 1.0
		sim._record_diagnostic("ضغط كامل على اللومبرياج (100%)", "وركتي على اللومبرياج حتى للقدام (100%). دابا الموطور معزول على الفيتيس، تقدر تبدل الفيتيس أو توقف بلا ما تسكت الطوموبيل.")
	)
	c_quick.add_child(btn_c100)

	var btn_cpat = Button.new()
	btn_cpat.text = "Patinage 52%"
	btn_cpat.pressed.connect(func():
		clutch_slider.value = 52.0
		sim.clutch_input = 0.52
		sim._record_diagnostic("تثبيت اللومبرياج فـ نقطة الوصل (Point de Patinage 52%)", "هزيتي اللومبرياج لـ 52% (نقطة الوصل). هنا الديسك ديال اللومبرياج كيبدا يتحك مع الموطور وكيحرك الطوموبيل بشوية بلا ما تسكت!")
	)
	c_quick.add_child(btn_cpat)

	var btn_c0 = Button.new()
	btn_c0.text = "0%"
	btn_c0.pressed.connect(func():
		clutch_slider.value = 0.0
		sim.clutch_input = 0.0
	)
	c_quick.add_child(btn_c0)

	# B) STEERING WHEEL (GUIDON : ربع دورة، نص دورة، دورة كاملة، دورة ونص)
	var steer_card = PanelContainer.new()
	steer_card.custom_minimum_size = Vector2(380, 220)
	steer_card.size_flags_vertical = Control.SIZE_SHRINK_END
	steer_card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.09, 0.15, 0.86), Color(0.45, 0.55, 0.70), 12))
	left_cluster.add_child(steer_card)

	var steer_vbox = VBoxContainer.new()
	steer_vbox.add_theme_constant_override("separation", 5)
	steer_card.add_child(steer_vbox)

	var st_head = Label.new()
	st_head.text = "🛞 الفولان (Guidon) — جر بصبعك أو ختار الدورة"
	st_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st_head.add_theme_font_size_override("font_size", 13)
	steer_vbox.add_child(st_head)

	turn_state_label = Label.new()
	turn_state_label.text = "مقاد نيشان (0°)"
	turn_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_state_label.add_theme_font_size_override("font_size", 14)
	turn_state_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	steer_vbox.add_child(turn_state_label)

	# Interactive touch drag pad for continuous steering wheel rotation
	var drag_pad = PanelContainer.new()
	drag_pad.custom_minimum_size = Vector2(350, 56)
	drag_pad.add_theme_stylebox_override("panel", _make_stylebox(Color(0.12, 0.16, 0.24), Color(0.88, 0.25, 0.25), 24, 2))
	steer_vbox.add_child(drag_pad)

	var drag_lbl = Label.new()
	drag_lbl.text = "⬅️ جر هنا لليسار أو اليمين باش تدور الفولان 3D ➡️"
	drag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag_lbl.add_theme_font_size_override("font_size", 12)
	drag_pad.add_child(drag_lbl)

	drag_pad.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			if event.pressed:
				is_dragging_wheel = true
				drag_start_x = event.position.x
				drag_start_deg = sim.steering_deg
			else:
				is_dragging_wheel = false
		elif event is InputEventMouseMotion and is_dragging_wheel:
			var dx = event.position.x - drag_start_x
			sim.steering_deg = clampf(drag_start_deg + dx * 2.4, -540.0, 540.0)
	)

	# Exact Turn Preset Buttons (ربع دورة، نص دورة، دورة كاملة)
	var turn_row1 = HBoxContainer.new()
	turn_row1.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_row1.add_theme_constant_override("separation", 4)
	steer_vbox.add_child(turn_row1)

	_add_turn_btn(turn_row1, "⬅️ دورة (360°)", -360.0, "دورتي الفولان دورة كاملة لليسار (360°): كتستعملها فـ التقاطع أو الدوار الصغير.")
	_add_turn_btn(turn_row1, "⬅️ نص دورة (180°)", -180.0, "دورتي الفولان نص دورة لليسار (180°): مثالية للمنعرجات ودخلة الرومبوان (الدوار).")
	_add_turn_btn(turn_row1, "⬅️ ربع (90°)", -90.0, "دورتي الفولان ربع دورة لليسار (90°): كتستعملها فـ الدوبلاج وتبدال المسلك فلوطوروت.")

	var turn_row2 = HBoxContainer.new()
	turn_row2.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_row2.add_theme_constant_override("separation", 4)
	steer_vbox.add_child(turn_row2)

	_add_turn_btn(turn_row2, "مقاد 0°", 0.0, "رديتي الفولان مقاد نيشان (0° - العلامة الحمراء الفوق فـ 12h).")
	_add_turn_btn(turn_row2, "ربع (90°) ➡️", 90.0, "دورتي الفولان ربع دورة لليمين (90°): مزيانة للرجوع للمسلك الأيمن فلوطوروت.")
	_add_turn_btn(turn_row2, "نص دورة (180°) ➡️", 180.0, "دورتي الفولان نص دورة لليمين (180°): مزيانة للخرجة من الدوار أو منعرج يمين.")
	_add_turn_btn(turn_row2, "دورة (360°) ➡️", 360.0, "دورتي الفولان دورة كاملة لليمين (360°): كتستعملها فـ دورة 90 درجة على اليمين.")

	# =========================================================================
	# 4. BOTTOM RIGHT: BOÎTE À VITESSES + BOULAT (LIGHTS) + FREIN & ACCÉLÉRATEUR
	# =========================================================================
	var right_cluster = HBoxContainer.new()
	right_cluster.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right_cluster.offset_right = -10
	right_cluster.offset_bottom = -8
	right_cluster.offset_top = -315
	right_cluster.offset_left = -640
	right_cluster.alignment = BoxContainer.ALIGNMENT_END
	right_cluster.add_theme_constant_override("separation", 8)
	ui_root.add_child(right_cluster)

	# A) LIGHTS (البولات والسينيالات) & GEARBOX (الفيتيس)
	var mid_right_card = PanelContainer.new()
	mid_right_card.custom_minimum_size = Vector2(360, 295)
	mid_right_card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.09, 0.15, 0.90), Color(0.45, 0.55, 0.70), 12))
	right_cluster.add_child(mid_right_card)

	var mr_vbox = VBoxContainer.new()
	mr_vbox.add_theme_constant_override("separation", 5)
	mid_right_card.add_child(mr_vbox)

	# Blinkers & Lights (البولات والسينيالات)
	var sig_row = HBoxContainer.new()
	sig_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sig_row.add_theme_constant_override("separation", 4)
	mr_vbox.add_child(sig_row)

	blinker_left_btn = Button.new()
	blinker_left_btn.text = "⬅️ سينيال يسار"
	blinker_left_btn.pressed.connect(func():
		sim.blinker_state = 0 if sim.blinker_state == -1 else -1
		sim._record_diagnostic("تشغيل السينيال الأيسر (Clignotant Gauche)", "درتي السينيال على اليسار: إجباري قبل ما تندمج فـ لوطوروت، قبل ما تدوبل، أولا ملي تبغي تدور على اليسار فـ الدوار.")
	)
	sig_row.add_child(blinker_left_btn)

	hazard_btn = Button.new()
	hazard_btn.text = "⚠️ الرباعية"
	hazard_btn.pressed.connect(func():
		sim.hazard_on = not sim.hazard_on
		sim._record_diagnostic("أضواء النجدة (الرباعية - Feux de détresse)", "كتشعل الرباعية ملي كتوقف فحالة استعجالية أولا ملي كتفاجأ بفرملة قوية فلوطوروت باش تنبه اللي موراك.")
	)
	sig_row.add_child(hazard_btn)

	blinker_right_btn = Button.new()
	blinker_right_btn.text = "سينيال يمين ➡️"
	blinker_right_btn.pressed.connect(func():
		sim.blinker_state = 0 if sim.blinker_state == 1 else 1
		sim._record_diagnostic("تشغيل السينيال الأيمن (Clignotant Droit)", "درتي السينيال على اليمين: إجباري قبل ما تخرج من الدوار (Rond-point)، قبل ما تشد اليمين، أولا باش تباركي.")
	)
	sig_row.add_child(blinker_right_btn)

	light_btn = Button.new()
	light_btn.text = "💡 البولات: الفيوز (Position)"
	light_btn.custom_minimum_size = Vector2(0, 34)
	light_btn.pressed.connect(func():
		sim.light_mode = (sim.light_mode + 1) % 4
		sim._record_diagnostic(
			"تغيير البولات لـ: " + sim.get_light_label(),
			"الفرق بين البولات فالمغرب:\n• الفيوز (Position): غير باش تبان الطوموبيل (150m).\n• الكود (Croisement): كيضوي 30 متر قدامك بلا ما يعمي الناس (إجباري بالليل فالمدينة).\n• الفار (Route): كيضوي 100 متر فاش تكون الطريق خاوية بالليل."
		)
	)
	mr_vbox.add_child(light_btn)

	# Gearbox Grid (Boîte à Vitesses: 1, 2, 3, 4, 5, N, R)
	var g_lbl = Label.new()
	g_lbl.text = "⚙️ علبة السرعات (ورك على اللومبرياج >80% عاد دوز الفيتيس)"
	g_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g_lbl.add_theme_font_size_override("font_size", 11)
	g_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))
	mr_vbox.add_child(g_lbl)

	var gear_grid = GridContainer.new()
	gear_grid.columns = 4
	gear_grid.add_theme_constant_override("h_separation", 5)
	gear_grid.add_theme_constant_override("v_separation", 5)
	mr_vbox.add_child(gear_grid)

	for g_val in [1, 3, 5, 0, 2, 4, -1]:
		var gb = Button.new()
		gb.custom_minimum_size = Vector2(78, 42)
		gb.text = "N (بامور)" if g_val == 0 else ("R (أريير)" if g_val == -1 else (str(g_val) + ("ère" if g_val == 1 else "ème")))
		var captured_g = g_val
		gb.pressed.connect(func(): sim.try_shift_gear(captured_g))
		gear_grid.add_child(gb)
		gear_buttons[g_val] = gb

	# Handbrake & Engine Start Row
	var hb_row = HBoxContainer.new()
	hb_row.add_theme_constant_override("separation", 6)
	mr_vbox.add_child(hb_row)

	handbrake_btn = Button.new()
	handbrake_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handbrake_btn.custom_minimum_size = Vector2(0, 40)
	handbrake_btn.text = "🛑 الفران د اليد: مرفوع (ON)"
	handbrake_btn.pressed.connect(func():
		sim.handbrake_on = not sim.handbrake_on
		if not sim.handbrake_on:
			sim.monitor_status = "info"
			sim.monitor_message = "✅ هبطتي الفران د اليد! دابا هز اللومبرياج بشوية لنقطة الوصل (50%) باش تتحرك الطوموبيل."
			sim._record_diagnostic("تهبيط الفران د اليد (Frein à main OFF)", "حيدتي الفران د اليد باش تحرر الرويض اللورانيين قبل الإقلاع.")
		else:
			sim._record_diagnostic("تطلاع الفران د اليد (Frein à main ON)", "طلعتي الفران د اليد باش تبلوكي الطوموبيل ما ترجعش للور فـ العقبة أو الوقوف.")
	)
	hb_row.add_child(handbrake_btn)

	engine_btn = Button.new()
	engine_btn.custom_minimum_size = Vector2(125, 40)
	engine_btn.text = "🔑 الموطور خدام"
	engine_btn.pressed.connect(func(): sim.restart_engine())
	hb_row.add_child(engine_btn)

	# B) FREIN (BRAKE) & ACCÉLÉRATEUR (GAS) PEDALS ON THE FAR RIGHT
	var pedals_card = PanelContainer.new()
	pedals_card.custom_minimum_size = Vector2(210, 295)
	pedals_card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.09, 0.16, 0.90), Color(0.45, 0.55, 0.70), 12))
	right_cluster.add_child(pedals_card)

	var p_hbox = HBoxContainer.new()
	p_hbox.add_theme_constant_override("separation", 8)
	pedals_card.add_child(p_hbox)

	# Brake Pedal Button (الفران)
	var brake_btn = Button.new()
	brake_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brake_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brake_btn.text = "🛑\nالفران\n(Frein)\n\nورك هنا"
	brake_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.55, 0.12, 0.14), Color(0.95, 0.32, 0.32), 12))
	brake_btn.button_down.connect(func():
		brake_held = true
		if sim.speed_kmh < 18.0 and sim.current_gear != 0 and sim.clutch_input < 0.70:
			sim.monitor_status = "warn"
			sim.monitor_message = "⚠️ راك كتفراني والسرعة هبطات! ورك على اللومبرياج 100% بالرجل اليسرى باش ما تسكتش الطوموبيل!"
	)
	brake_btn.button_up.connect(func(): brake_held = false)
	p_hbox.add_child(brake_btn)

	# Gas Pedal Button (الأكسيليراتور)
	var gas_btn = Button.new()
	gas_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gas_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gas_btn.text = "🚀\nأكسيليراتور\n(Gas)\n\nورك هنا"
	gas_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.10, 0.48, 0.22), Color(0.28, 0.92, 0.48), 12))
	gas_btn.button_down.connect(func(): throttle_held = true)
	gas_btn.button_up.connect(func(): throttle_held = false)
	p_hbox.add_child(gas_btn)

	# =========================================================================
	# 5. INTERACTIVE "❓ علاش؟ / شرح ليا هاد الحركة" DIAGNOSTIC & CLUTCH LAB MODAL
	# =========================================================================
	_build_why_modal()

	# =========================================================================
	# 6. MOROCCAN DRIVING LOBBY & ENCYCLOPEDIA (اللوبي وموسوعة السياقة بالمغرب)
	# =========================================================================
	_build_lobby_overlay()

func _add_turn_btn(parent: Control, label_txt: String, target_deg: float, why_msg: String) -> void:
	var b = Button.new()
	b.text = label_txt
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(func():
		sim.steering_deg = target_deg
		sim._record_diagnostic("تدوير الفولان: " + label_txt, why_msg)
	)
	parent.add_child(b)

func _build_why_modal() -> void:
	why_modal = PanelContainer.new()
	why_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	why_modal.offset_left = 40
	why_modal.offset_right = -40
	why_modal.offset_top = 24
	why_modal.offset_bottom = -24
	why_modal.visible = false
	why_modal.add_theme_stylebox_override("panel", _make_stylebox(Color(0.04, 0.08, 0.15, 0.97), Color(1.0, 0.78, 0.22), 16, 3))
	ui_root.add_child(why_modal)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	why_modal.add_child(vbox)

	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title = Label.new()
	title.text = "🧠 المونيتور الذكي: «علاش درتي هاد الحركة؟ وشنو واقع فـ اللومبرياج والموطور؟»"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "✖ رجوع للسياقة"
	close_btn.custom_minimum_size = Vector2(140, 38)
	close_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.75, 0.15, 0.15), Color(1, 0.5, 0.5), 8))
	close_btn.pressed.connect(func(): why_modal.visible = false)
	header.add_child(close_btn)

	# Visual Mechanical Clutch Disc Diagram (الموطور ↔ ديسك اللومبرياج ↔ الفيتيس والرويض)
	var mech_panel = PanelContainer.new()
	mech_panel.custom_minimum_size = Vector2(0, 74)
	mech_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.08, 0.13, 0.22), Color(0.25, 0.65, 0.95), 10))
	vbox.add_child(mech_panel)

	var mech_vbox = VBoxContainer.new()
	mech_panel.add_child(mech_vbox)

	clutch_status_lbl = Label.new()
	clutch_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clutch_status_lbl.add_theme_font_size_override("font_size", 14)
	clutch_status_lbl.add_theme_color_override("font_color", Color(0.35, 0.98, 0.55))
	mech_vbox.add_child(clutch_status_lbl)

	var plates_row = HBoxContainer.new()
	plates_row.alignment = BoxContainer.ALIGNMENT_CENTER
	plates_row.add_theme_constant_override("separation", 12)
	mech_vbox.add_child(plates_row)

	var motor_lbl = Label.new()
	motor_lbl.text = "🔥 الموطور (Volant Moteur) ➔"
	plates_row.add_child(motor_lbl)

	clutch_plate_motor = ColorRect.new()
	clutch_plate_motor.custom_minimum_size = Vector2(85, 24)
	clutch_plate_motor.color = Color(0.95, 0.35, 0.15)
	plates_row.add_child(clutch_plate_motor)

	clutch_plate_disc = ColorRect.new()
	clutch_plate_disc.custom_minimum_size = Vector2(85, 24)
	clutch_plate_disc.color = Color(0.20, 0.85, 0.45)
	plates_row.add_child(clutch_plate_disc)

	var wheels_lbl = Label.new()
	wheels_lbl.text = "⬅ ⚙️ علبة السرعات والرويض (Boîte & Roues)"
	plates_row.add_child(wheels_lbl)

	why_text_label = RichTextLabel.new()
	why_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	why_text_label.add_theme_font_size_override("normal_font_size", 15)
	vbox.add_child(why_text_label)

func _open_why_modal() -> void:
	why_text_label.text = sim.build_live_why_explanation()
	var pct = int(sim.clutch_input * 100.0)
	if sim.clutch_input >= 0.80:
		clutch_status_lbl.text = "🔵 الرسم الميكانيكي: اللومبرياج مضغوط (" + str(pct) + "%) — الديسك مفصول تماماً على الموطور (تقدر تبدل الفيتيس بأمان)"
		clutch_plate_disc.color = Color(0.25, 0.65, 0.98)
	elif sim.clutch_input >= 0.35:
		clutch_status_lbl.text = "🟢 الرسم الميكانيكي: نقطة الوصل Patinage (" + str(pct) + "%) — الديسك كيتحك بشوية مع الموطور وكيحرك الطوموبيل بنعومة!"
		clutch_plate_disc.color = Color(0.20, 0.95, 0.45)
	else:
		clutch_status_lbl.text = "🟠 الرسم الميكانيكي: اللومبرياج مطلوق (" + str(pct) + "%) — الديسك لاصق 100% مع الموطور!"
		clutch_plate_disc.color = Color(0.95, 0.65, 0.15)
	why_modal.visible = true

func _build_lobby_overlay() -> void:
	lobby_panel = PanelContainer.new()
	lobby_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.04, 0.07, 0.13, 0.96), Color(0.85, 0.18, 0.20), 0, 3))
	ui_root.add_child(lobby_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	lobby_panel.add_child(main_vbox)

	# Lobby Header
	var header_panel = PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.10, 0.16, 0.28), Color(0.22, 0.65, 0.42), 10, 2))
	main_vbox.add_child(header_panel)

	var h_row = HBoxContainer.new()
	header_panel.add_child(h_row)

	var title_lbl = Label.new()
	title_lbl.text = "🇲🇦 مدرسة السياقة المغربية 3D (Siya9a Maroc 3D - Casa ↔ Autoroute A1 ↔ Rabat)"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 19)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.30))
	h_row.add_child(title_lbl)

	var resume_btn = Button.new()
	resume_btn.text = "▶️ ابدأ / كمّل السياقة دابا"
	resume_btn.custom_minimum_size = Vector2(190, 40)
	resume_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.12, 0.62, 0.28), Color(0.45, 0.98, 0.58), 8))
	resume_btn.pressed.connect(func(): lobby_panel.visible = false)
	h_row.add_child(resume_btn)

	# Split Content: Left = 4 OpenStreetMap Driving Routes | Right = Moroccan Driving Encyclopedia
	var split = HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	main_vbox.add_child(split)

	# LEFT COLUMN: 4 Routes (Circuit Permis, Casa OSM, Autoroute A1 Casa-Rabat OSM, Rabat Night OSM)
	var routes_panel = PanelContainer.new()
	routes_panel.custom_minimum_size = Vector2(540, 0)
	routes_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.07, 0.11, 0.19), Color(0.25, 0.45, 0.72), 10))
	split.add_child(routes_panel)

	var r_vbox = VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 6)
	routes_panel.add_child(r_vbox)

	var r_head = Label.new()
	r_head.text = "🛣️ ختار الطريق أو الوضع التطبيقي (خرائط OpenStreetMap المغرب):"
	r_head.add_theme_font_size_override("font_size", 15)
	r_head.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	r_vbox.add_child(r_head)

	for route in MoroccoData.get_routes_catalog():
		var card = PanelContainer.new()
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _make_stylebox(Color(0.11, 0.17, 0.28), Color(0.32, 0.55, 0.82), 8, 1))
		r_vbox.add_child(card)

		var chbox = HBoxContainer.new()
		card.add_child(chbox)

		var cvbox = VBoxContainer.new()
		cvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chbox.add_child(cvbox)

		var rt_title = Label.new()
		rt_title.text = route["title"]
		rt_title.add_theme_font_size_override("font_size", 14)
		rt_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.40))
		cvbox.add_child(rt_title)

		var rt_sub = Label.new()
		rt_sub.text = route["subtitle"] + "\n" + route["description"]
		rt_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt_sub.add_theme_font_size_override("font_size", 11)
		rt_sub.add_theme_color_override("font_color", Color(0.82, 0.88, 0.95))
		cvbox.add_child(rt_sub)

		var play_btn = Button.new()
		play_btn.text = "🚗 سوق هنا"
		play_btn.custom_minimum_size = Vector2(105, 52)
		play_btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.14, 0.55, 0.28), Color(0.35, 0.92, 0.52), 8))
		var r_id = route["id"]
		play_btn.pressed.connect(func(): _load_driving_mode(r_id, false))
		chbox.add_child(play_btn)

	# RIGHT COLUMN: Moroccan Driving School Encyclopedia (موسوعة السياقة في المغرب)
	var enc_panel = PanelContainer.new()
	enc_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enc_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.07, 0.11, 0.19), Color(0.95, 0.72, 0.20), 10))
	split.add_child(enc_panel)

	var e_vbox = VBoxContainer.new()
	e_vbox.add_theme_constant_override("separation", 6)
	enc_panel.add_child(e_vbox)

	var e_head = Label.new()
	e_head.text = "📘 موسوعة تعليم السياقة في المغرب (اللومبرياج • الفولان • البولات • لوطوروت):"
	e_head.add_theme_font_size_override("font_size", 15)
	e_head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.28))
	e_vbox.add_child(e_head)

	var tabs_grid = GridContainer.new()
	tabs_grid.columns = 2
	tabs_grid.add_theme_constant_override("h_separation", 6)
	tabs_grid.add_theme_constant_override("v_separation", 4)
	e_vbox.add_child(tabs_grid)

	var lessons = MoroccoData.get_encyclopedia_lessons()
	lesson_content_lbl = RichTextLabel.new()
	lesson_content_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lesson_content_lbl.add_theme_font_size_override("normal_font_size", 14)

	for lesson in lessons:
		var tb = Button.new()
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 34)
		tb.text = lesson["title"]
		tb.add_theme_font_size_override("font_size", 12)
		var l_data = lesson
		tb.pressed.connect(func():
			lesson_content_lbl.text = "📌 " + l_data["title"] + "\n" + l_data["summary"] + "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" + l_data["content"]
		)
		tabs_grid.add_child(tb)

	e_vbox.add_child(lesson_content_lbl)
	if lessons.size() > 0:
		var first_l = lessons[0]
		lesson_content_lbl.text = "📌 " + first_l["title"] + "\n" + first_l["summary"] + "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" + first_l["content"]

func _update_ui_labels() -> void:
	if not speed_label:
		return
	speed_label.text = str(int(round(abs(sim.speed_kmh)))) + " كم/س"
	rpm_label.text = str(int(round(sim.rpm))) + " RPM"
	gear_badge_label.text = "R" if sim.current_gear == -1 else ("N" if sim.current_gear == 0 else str(sim.current_gear))
	turn_state_label.text = "🛞 " + sim.get_steering_turn_label()

	var pct = int(round(sim.clutch_input * 100.0))
	if sim.clutch_input >= 0.80:
		clutch_pct_label.text = str(pct) + "% (موروك كامل)"
		clutch_pct_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	elif sim.clutch_input >= 0.35:
		clutch_pct_label.text = "🟢 " + str(pct) + "% (Patinage!)"
		clutch_pct_label.add_theme_color_override("font_color", Color(0.25, 0.98, 0.45))
	else:
		clutch_pct_label.text = str(pct) + "% (مطلوق)"
		clutch_pct_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.30))

	light_btn.text = "💡 البولات: " + sim.get_light_label()
	handbrake_btn.text = "🛑 الفران د اليد: مرفوع (ON)" if sim.handbrake_on else "✅ الفران د اليد: مهبط (OFF)"
	engine_btn.text = "🔑 الموطور خدام" if sim.engine_running else "🚨 ديماري الموطور (Calé!)"

	for g_key in gear_buttons.keys():
		var btn: Button = gear_buttons[g_key]
		if g_key == sim.current_gear:
			btn.add_theme_stylebox_override("normal", _make_stylebox(Color(0.16, 0.65, 0.32), Color(0.55, 1.0, 0.65), 6))
		else:
			btn.remove_theme_stylebox_override("normal")

	monitor_label.text = "👨‍🏫 المونيتور: " + sim.monitor_message
	match sim.monitor_status:
		"good":
			monitor_banner.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.28, 0.14, 0.92), Color(0.25, 0.95, 0.48), 8))
		"warn":
			monitor_banner.add_theme_stylebox_override("panel", _make_stylebox(Color(0.32, 0.22, 0.05, 0.92), Color(0.98, 0.78, 0.20), 8))
		"error":
			monitor_banner.add_theme_stylebox_override("panel", _make_stylebox(Color(0.38, 0.08, 0.08, 0.94), Color(1.0, 0.32, 0.32), 8))
		_:
			monitor_banner.add_theme_stylebox_override("panel", _make_stylebox(Color(0.06, 0.14, 0.24, 0.88), Color(0.25, 0.75, 0.98), 8))
