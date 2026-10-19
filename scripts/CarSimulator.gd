class_name CarSimulator
extends RefCounted

# Controls state
var clutch_input: float = 1.0        # 1.0 = fully pressed (موروك عليه 100%), 0.0 = released (مطلوق)
var brake_input: float = 0.0         # 0.0 .. 1.0
var throttle_input: float = 0.0      # 0.0 .. 1.0
var steering_deg: float = 0.0        # -540.0 .. +540.0 degrees (1.5 turns each way)
var current_gear: int = 0            # -1 = R, 0 = N (Point Mort), 1..5 = 1ère..5ème
var handbrake_on: bool = true        # الفران د اليد
var engine_running: bool = true
var engine_stalled: bool = false

# Lights & signals (البولات والسينيالات)
var light_mode: int = 1              # 0=Off, 1=Feux de position (الفيوز), 2=Code (الكود), 3=Phare (الفار)
var blinker_state: int = 0           # -1=Left, 0=Off, 1=Right
var hazard_on: bool = false          # الرباعية

# Physics & Telemetry
var speed_kmh: float = 0.0
var rpm: float = 850.0
var pos_3d: Vector3 = Vector3(3.2, 0.0, -5.0)
var heading_rad: float = 0.0         # 0 = facing -Z (north along the road)
var current_slope_deg: float = 0.0
var distance_traveled_m: float = 0.0
var patinage_hold_time: float = 0.0
var prev_clutch: float = 1.0

# Instructor live feedback & "علاش؟ / شرح ليا" diagnostic memory
var monitor_message: String = "مرحبا بيك فـ مدرسة السياقة! اللومبرياج موروك 100%، دوز الفيتيس لـ 1ère، حيد الفران د اليد، وهز رجلك بشوية حتى لنقطة الوصل (Patinage)."
var monitor_status: String = "info"  # "good", "warn", "error", "info"
var last_event_title: String = "بداية الحصة التطبيقية"
var last_event_why: String = "اللومبرياج دابا مضغوط 100%، يعني الموطور مفصول على الرويض. باش تتحرك الطوموبيل بلا ما تسكت، خاصك تدوز البروميير (1ère) وتهز رجلك على اللومبرياج بشوية حتى لنقطة الوصل (ما بين 40% و 65%)."
var action_history: Array = []

const GEAR_MAX_SPEED = {
	-1: 22.0,
	0: 0.0,
	1: 26.0,
	2: 48.0,
	3: 75.0,
	4: 105.0,
	5: 140.0
}

const GEAR_MIN_SPEED = {
	-1: 0.0,
	0: 0.0,
	1: 0.0,
	2: 12.0,
	3: 30.0,
	4: 52.0,
	5: 78.0
}

func reset_for_route(start_pos: Vector3, start_heading: float = 0.0) -> void:
	pos_3d = start_pos
	heading_rad = start_heading
	speed_kmh = 0.0
	rpm = 850.0
	clutch_input = 1.0
	prev_clutch = 1.0
	brake_input = 0.0
	throttle_input = 0.0
	steering_deg = 0.0
	current_gear = 0
	handbrake_on = true
	engine_running = true
	engine_stalled = false
	distance_traveled_m = 0.0
	monitor_status = "info"
	monitor_message = "الطوموبيل واجدة! 1) خلي اللومبرياج موروك 100%  2) دير 1ère  3) حيد الفران د اليد  4) هز اللومبرياج لنقطة الوصل (50%)."
	_record_diagnostic(
		"استعداد للإقلاع (Démarrage)",
		"وركتي على اللومبرياج 100% باش تفصل الموطور على علبة السرعات. دابا تقدر تدوز الفيتيس 1ère بأمان بلا ما يتسمع كراطاج."
	)

func restart_engine() -> void:
	if current_gear != 0 and clutch_input < 0.8:
		monitor_status = "warn"
		monitor_message = "⚠️ باش تديماري الموطور، ضروري إما دير النقطة الميتة (N) أولا تورك على اللومبرياج 100%!"
		_record_diagnostic(
			"محاولة تشغيل الموطور والفيتيس دايز بلا لومبرياج",
			"ملي كتبغي تضور الساروت (Contact) والفيتيس دايز، إلا ما وركتيش على اللومبرياج غادي تنقز الطوموبيل لقدام! لذلك ديما ورك على اللومبرياج 100% أو دير البامور (N) قبل ما تديماري."
		)
		return
	engine_running = true
	engine_stalled = false
	rpm = 850.0
	monitor_status = "good"
	monitor_message = "✅ الموطور خدم! ورك على اللومبرياج 100%، دير 1ère، وهز رجلك بشوية لنقطة الوصل."
	_record_diagnostic(
		"إعادة تشغيل الموطور بنجاح (Contact ON)",
		"شغلتي الموطور وأنت عازل الحركة باللومبرياج/البامور. دابا الديسك ديال الموطور كيدور بـ 850 دورة فالدقيقة (Ralenti) ومستعد للوصل."
	)

func try_shift_gear(target_gear: int) -> void:
	if target_gear == current_gear:
		return
	var gear_label = get_gear_name(target_gear)
	# Rule 1: Must press clutch >= 78% to shift!
	if engine_running and clutch_input < 0.78:
		monitor_status = "error"
		monitor_message = "❌ كراطي الفيتيس! بغيتي تدوز لـ " + gear_label + " وأنت ما موركش على اللومبرياج (خاصك تورك فوق 80%)!"
		_record_diagnostic(
			"خطأ: تبدال الفيتيس بلا لومبرياج (Craquage de boîte)",
			"علاش وقع هاد المشكل؟ حيت جربتي تدوز الفيتيس لـ (" + gear_label + ") ورجلك اليسرى ما ضاغطاش على اللومبرياج كفاية (" + str(int(clutch_input * 100)) + "% فقط). ميكانيكياً: المسننات (Pignons) ديال الفيتيس كيدورو بسرعة الموطور، وملي ما كتفصلهمش باللومبرياج كيتحكو ببعضياتهم وكيديرو صوت الكراطاج!"
		)
		return

	# Rule 2: Reverse gear while moving forward
	if target_gear == -1 and speed_kmh > 3.0:
		monitor_status = "error"
		monitor_message = "❌ مستحيل تدوز مارش أريير (R) والطوموبيل غادية لقدام! وقف تماماً بـ اللومبرياج + الفران."
		_record_diagnostic(
			"خطأ: محاولة دوزان مارش أريير (R) والطوموبيل متحركة",
			"المارش أريير ما فيهش السانكرونيزور بحال الفيتيسات لقدام، خاص الطوموبيل تكون واقفة تماماً (0 كم/س) واللومبرياج موروك 100% عاد تدوز R."
		)
		return

	var old_gear = current_gear
	current_gear = target_gear

	if target_gear == 0:
		monitor_status = "info"
		monitor_message = "ℹ️ النقطة الميتة (Point Mort - N): الموطور مفصول على الرويض."
		_record_diagnostic(
			"الرجوع للنقطة الميتة (Point Mort - N)",
			"درتي البامور (N) من بعد ما وركتي على اللومبرياج. هاد الحركة مزيانة ملي كتكون واقف فـ الضو الأحمر طويل أو فاش كتبغي توقف وتطلع الفران د اليد."
		)
	elif target_gear == 1 and abs(speed_kmh) < 5.0:
		monitor_status = "good"
		monitor_message = "✅ دوزتي 1ère مزيان! دابا حيد الفران د اليد وهز اللومبرياج بشوية حتى لنقطة الوصل (المنطقة الخضراء 45%-65%)."
		_record_diagnostic(
			"دوزان الفيتيس الأول (1ère) للإقلاع",
			"علاش هاد الحركة صحيحة؟ حيت وركتي على اللومبرياج (" + str(int(clutch_input * 100)) + "%) وفصلتي الموطور، ودوزتي 1ère اللي كيعطي أكبر قوة عزم (Couple) باش يجر وزن الطوموبيل من الوقوف."
		)
	elif target_gear > old_gear and target_gear >= 2:
		var min_s = GEAR_MIN_SPEED.get(target_gear, 20.0)
		if speed_kmh < min_s - 5.0:
			monitor_status = "warn"
			monitor_message = "⚠️ طلعتي لـ " + gear_label + " بكري بزاف! سرعتك غير " + str(int(speed_kmh)) + " كم/س (خاصك على الأقل " + str(int(min_s)) + " كم/س)."
			_record_diagnostic(
				"تبدال الفيتيس الفوق قبل الوقت (Sous-régime)",
				"طلعتي لـ " + gear_label + " وسرعة الطوموبيل باقا قليلة (" + str(int(speed_kmh)) + " كم/س). علاش ما خاصكش تطلع الفيتيس دابا؟ حيت الموطور غيهبط لـ قل من 1200 دورة/دقيقة وغيبدا يترعد وتفقد الطوموبيل القوة ديالها!"
			)
		else:
			monitor_status = "good"
			monitor_message = "👏 ممتاز! طلعتي لـ " + gear_label + " فـ الوقت المناسب (" + str(int(speed_kmh)) + " كم/س). طلق اللومبرياج بسلاسة."
			_record_diagnostic(
				"تبدال الفيتيس بنجاح لـ " + gear_label,
				"وركتي على اللومبرياج 100%، طلعتي لـ " + gear_label + " فـ سرعة " + str(int(speed_kmh)) + " كم/س باش تريح الموطور وتنقص استهلاك المازوط/ليصانص."
			)
	elif target_gear < old_gear and target_gear >= 1:
		monitor_status = "good"
		monitor_message = "✅ كراطيتي (Rétrogradage) لـ " + gear_label + "! هادشي كيعاون بـ الفران د الموطور قبل الدورة أو الدوار."
		_record_diagnostic(
			"تخفيض الفيتيس (Rétrogradage) لـ " + gear_label,
			"علاش كراطي الفيتيس؟ ملي كتنقص السرعة قبل الدوار (Rond-point) أو محطة الأداء، خاصك تهبط الفيتيس (مثلا من 3 لـ 2) باش تستافد من «الفران د الموطور» وتكون الطوموبيل مستعدة تكمل الطريق بلا ما تفشل."
		)

func step_physics(delta: float) -> void:
	var clutch_delta = (clutch_input - prev_clutch) / maxf(delta, 0.001)
	prev_clutch = clutch_input

	if not engine_running:
		rpm = move_toward(rpm, 0.0, delta * 1500.0)
		var decel = 4.0 + brake_input * 18.0 + (12.0 if handbrake_on else 0.0)
		speed_kmh = move_toward(speed_kmh, 0.0, decel * delta)
		_integrate_motion(delta)
		return

	# Check clutch bite point (Point de Patinage: 0.35 <= clutch_input <= 0.68)
	var in_patinage: bool = (clutch_input >= 0.35 and clutch_input <= 0.68)
	var engagement: float = clampf(1.0 - clutch_input, 0.0, 1.0) # 0 = disengaged, 1 = fully engaged

	if current_gear == 0 or clutch_input > 0.85:
		# Engine disconnected from wheels
		var target_rpm = 850.0 + throttle_input * 4800.0
		rpm = lerpf(rpm, target_rpm, delta * 6.0)
		var coast_decel = 2.2 + brake_input * 26.0 + (18.0 if handbrake_on else 0.0) + sin(deg_to_rad(current_slope_deg)) * 12.0
		speed_kmh = move_toward(speed_kmh, 0.0, maxf(1.0, coast_decel) * delta)
	else:
		# Gear engaged or in patinage
		# Check for STALL (Calage) conditions!
		if abs(speed_kmh) < 4.5 and current_gear != 0:
			# Condition A: Dumped clutch too fast from standstill without enough gas or in high gear
			if clutch_input < 0.28 and throttle_input < 0.08 and abs(speed_kmh) < 2.0:
				_trigger_stall(
					"سكتات ليك الطوموبيل (Calage)! طلقتي اللومبرياج دقة وحدة بلا ما تثبت فـ نقطة الوصل وبلا أكسيليراتور!",
					"علاش سكتات الطوموبيل؟ حيت هزيتي رجلك اليسرى على اللومبرياج حتى لـ (" + str(int(clutch_input * 100)) + "%) والطوموبيل باقا ثقيلة فبلاصتها (0 كم/س) وبلا ما تعطي أكسيليراتور كافي. الديسك ديال اللومبرياج لصق دقة وحدة على الموطور ووقفو!"
				)
				return
			# Condition B: Trying to start from 0 km/h in 3rd, 4th, or 5th gear!
			if current_gear >= 3 and clutch_input < 0.55 and abs(speed_kmh) < 6.0:
				_trigger_stall(
					"سكتات الطوموبيل! بغيتي تقلع من الوقوف بـ الفيتيس " + str(current_gear) + "ème عوض 1ère!",
					"علاش سكتات؟ الفيتيس " + str(current_gear) + "ème مصاوب للسرعة العالية ماشي للإقلاع! الإقلاع من 0 كم/س ديما كيكون بـ 1ère (البروميير)."
				)
				return
			# Condition C: Handbrake still pulled while releasing clutch!
			if handbrake_on and clutch_input < 0.35 and throttle_input > 0.1:
				_trigger_stall(
					"سكتات الطوموبيل! نسيتي الفران د اليد (Frein à main) مطلع وأنت كتهز اللومبرياج!",
					"علاش سكتات؟ حيت الرويض اللورانيين مبلوكيين بـ الفران د اليد وأنت طلقتي اللومبرياج باش تزيد. ديما هبط الفران د اليد قبل ما تفوت نقطة الوصل!"
				)
				return
			# Condition D: Braking hard to 0 km/h without pressing clutch!
			if brake_input > 0.5 and clutch_input < 0.45 and abs(speed_kmh) < 2.5:
				_trigger_stall(
					"سكتات الطوموبيل فـ الوقوف! فرانتي حتى وقفتي وبقيتي شابك الفيتيس بلا ما تورك على اللومبرياج!",
					"قاعدة ذهبية فـ السياقة: ملي كتفراني باش توقف، غير تهبط السرعة لـ قل من 15 كم/س، ضروري تورك على اللومبرياج 100% بالرجل اليسرى باش تعزل الموطور وما يسكتش ليك!"
				)
				return

		# Track smooth patinage take-off
		if in_patinage and abs(speed_kmh) < 12.0 and current_gear == 1 and not handbrake_on:
			patinage_hold_time += delta
			if patinage_hold_time > 0.4 and patinage_hold_time < 0.6:
				monitor_status = "good"
				monitor_message = "🟢 برافو! راك شاد نقطة الوصل (Point de Patinage)! زيد شوية أكسيليراتور وكمل هز اللومبرياج بشوية."
				_record_diagnostic(
					"نجاح فـ نقطة الوصل (Point de Patinage المثالي)",
					"علاش الطوموبيل تحركات بسلاسة بلا ما تسكت؟ حيت حبستي رجلك اليسرى فـ منطقة الباتيناج (" + str(int(clutch_input * 100)) + "%)، فهاد اللحظة الديسك ديال اللومبرياج كيتحك بشوية مع الموطور وكينقل الحركة للرويض بالتدريج!"
				)

		# Calculate speed acceleration based on gear, engagement, throttle, and brake
		var max_gear_spd: float = GEAR_MAX_SPEED.get(current_gear, 40.0)
		var dir_sign: float = -1.0 if current_gear == -1 else 1.0

		# Creep speed in 1st or R at patinage even with 0 throttle (like real diesel Auto-Ecole Dacia/Clio!)
		var creep_pull: float = 0.0
		if (current_gear == 1 or current_gear == -1) and abs(speed_kmh) < 9.0 and engagement > 0.25 and not handbrake_on and brake_input < 0.1:
			creep_pull = 5.5 * engagement

		var drive_accel: float = (throttle_input * 24.0 * engagement + creep_pull) * (1.25 / maxf(1.0, float(abs(current_gear)) * 0.55))
		var brake_decel: float = brake_input * 32.0 + (22.0 if handbrake_on else 0.0)
		var engine_drag: float = (1.0 - throttle_input) * 3.5 * engagement
		var slope_drag: float = sin(deg_to_rad(current_slope_deg)) * 14.0

		if current_gear > 0:
			speed_kmh += (drive_accel - brake_decel - engine_drag - slope_drag) * delta
			speed_kmh = clampf(speed_kmh, 0.0, max_gear_spd)
		elif current_gear == -1:
			speed_kmh -= (drive_accel - brake_decel - engine_drag) * delta
			speed_kmh = clampf(speed_kmh, -max_gear_spd, 0.0)

		# Update RPM from wheel speed + clutch slip
		var gear_ratio_rpm = 900.0 + (abs(speed_kmh) / maxf(1.0, max_gear_spd)) * 4200.0
		var free_rpm = 850.0 + throttle_input * 4800.0
		rpm = lerpf(free_rpm, gear_ratio_rpm, engagement)
		rpm = clampf(rpm, 650.0, 6200.0)

		# Coach prompt if RPM is too high in current gear
		if rpm > 4100.0 and current_gear >= 1 and current_gear < 5 and clutch_input < 0.3:
			monitor_status = "warn"
			monitor_message = "🔊 الموطور كيغوت (" + str(int(rpm)) + " RPM)! ورك على اللومبرياج 100% ودوز لـ " + str(current_gear + 1) + "ème!"

	_integrate_motion(delta)

func _trigger_stall(msg: String, why_detail: String) -> void:
	engine_running = false
	engine_stalled = true
	rpm = 0.0
	speed_kmh = 0.0
	monitor_status = "error"
	monitor_message = "🛑 " + msg + " (كليكي على «ديماري الموطور» أو «علاش؟» باش تفهم)"
	_record_diagnostic("سكتات الطوموبيل (Calage du moteur)", why_detail)

func _integrate_motion(delta: float) -> void:
	var speed_ms = speed_kmh / 3.6
	distance_traveled_m += abs(speed_ms) * delta
	# Bicycle steering model: steering_deg (-540..540) maps to front wheel angle (-34..+34 deg)
	var front_wheel_rad = deg_to_rad((steering_deg / 540.0) * 34.0)
	var wheelbase = 2.58
	if abs(speed_ms) > 0.02:
		var angular_vel = (speed_ms / wheelbase) * tan(front_wheel_rad)
		heading_rad -= angular_vel * delta
		var forward_dir = Vector3(-sin(heading_rad), 0.0, -cos(heading_rad))
		pos_3d += forward_dir * speed_ms * delta

func _record_diagnostic(title: String, detail: String) -> void:
	last_event_title = title
	last_event_why = detail
	action_history.push_front({"title": title, "detail": detail})
	if action_history.size() > 6:
		action_history.pop_back()

func get_gear_name(g: int) -> String:
	if g == -1:
		return "R (مارش أريير)"
	elif g == 0:
		return "N (بامور)"
	elif g == 1:
		return "1ère (بروميير)"
	else:
		return str(g) + "ème"

func get_steering_turn_label() -> String:
	var abs_deg = abs(steering_deg)
	var dir_txt = "لليسار ⬅️" if steering_deg < -15.0 else ("لليمين ➡️" if steering_deg > 15.0 else "")
	if abs_deg < 22.0:
		return "مقاد نيشان (0°)"
	elif abs_deg < 115.0:
		return "ربع دورة (1/4) " + dir_txt + " [" + str(int(abs_deg)) + "°]"
	elif abs_deg < 245.0:
		return "نص دورة (1/2) " + dir_txt + " [" + str(int(abs_deg)) + "°]"
	elif abs_deg < 420.0:
		return "دورة كاملة (1 Tour) " + dir_txt + " [" + str(int(abs_deg)) + "°]"
	else:
		return "دورة ونص أقصى الفولان (1.5 Tour) " + dir_txt + " [" + str(int(abs_deg)) + "°]"

func get_clutch_zone_label() -> String:
	var pct = int(round(clutch_input * 100.0))
	if clutch_input >= 0.80:
		return "مضغوط كامل (" + str(pct) + "%) — الموطور معزول (تقدر تبدل الفيتيس)"
	elif clutch_input >= 0.35:
		return "🟢 نقطة الوصل Patinage (" + str(pct) + "%) — الديسك كيجر الطوموبيل!"
	else:
		return "مطلوق (" + str(pct) + "%) — الموطور شابك 100% مع الرويض"

func get_light_label() -> String:
	match light_mode:
		0: return "طافيين (Off)"
		1: return "الفيوز (Feux de position)"
		2: return "الكود (Croisement - 30m)"
		3: return "الفار (Phare / Route - 100m)"
	return "الفيوز"

func build_live_why_explanation() -> String:
	var text = "🔍 تشخيص فوري لحالتك دابا («علاش درتي هاد الحركة؟»):\n"
	text += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	text += "📌 آخر حدث تسجل: " + last_event_title + "\n"
	text += "💡 الشرح الميكانيكي والتطبيقي:\n" + last_event_why + "\n\n"
	text += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	text += "⚙️ حالة الطوموبيل ديالك فهاد اللحظة بالضبط:\n"
	text += "• 🦶 اللومبرياج (Embrayage): " + get_clutch_zone_label() + "\n"
	if clutch_input >= 0.80:
		text += "   👈 علاش وركتي عليه كامل؟ حيت ملي كتورك فوق 80%، كتفصل الديسك ديال الموطور على الفيتيس، وهادشي كيخليك تبدل الفيتيس أولا توقف بلا ما يسكت الموطور.\n"
	elif clutch_input >= 0.35:
		text += "   👈 علاش راك فـ نقطة الوصل (Patinage)؟ هادي هي أهم مرحلة فالإقلاع والعقبة والدوار الثقيل: نص الحركة كيدوز للرويض باش تتحرك الطوموبيل بنعومة بلا ما تنقز.\n"
	else:
		text += "   👈 علاش اللومبرياج مطلوق؟ ملي كتكون الطوموبيل غادية فوق 15 كم/س وكملتي تبدال الفيتيس، خاصك تحيد رجلك على اللومبرياج باش ما يتحرقش الديسك.\n"

	text += "\n• 🛞 الفولان (Guidon): " + get_steering_turn_label() + "\n"
	var abs_deg = abs(steering_deg)
	if abs_deg < 22.0:
		text += "   👈 الفولان مقاد: مزيان للسير فخط مستقيم. العلامة الحمراء الفوق فـ 12h كتعاونك تعرف أن الرويض مقادين.\n"
	elif abs_deg < 115.0:
		text += "   👈 ربع دورة: مثالية لتبدال المسلك فـ لوطوروت كازا-الرباط أو تصحيح المسار بلا خطورة.\n"
	elif abs_deg < 245.0:
		text += "   👈 نص دورة (180°): هي اللي كتستعمل باش تدخل وتدور فـ الرومبوان (الدوار) أو المنعرجات الحضرية.\n"
	else:
		text += "   👈 دورة كاملة / دورة ونص: كتستعملها فـ التقاطعات الضيقة، الكراج، والباركينغ بسرعة قليلة (1ère أو R).\n"

	text += "\n• ⚙️ الفيتيس الحالي: " + get_gear_name(current_gear) + " | السرعة: " + str(int(speed_kmh)) + " كم/س | الموطور: " + str(int(rpm)) + " RPM\n"
	text += "• 💡 البولات: " + get_light_label() + " | السينيال: " + ("اليسار ⬅️" if blinker_state == -1 else ("اليمين ➡️" if blinker_state == 1 else "طافي")) + "\n"
	return text
