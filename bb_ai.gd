extends Node
## CPU opponent for Block Brawl (drives a bb_fighter.gd through its AI input
## hooks: ai_ix/ai_iy movement + ai_press() attack buffer, so cooldowns,
## recovery, whiffs and hit rules apply exactly as for a human player).
##
## Decision making is FSM + utility scoring, NOT one giant conditional:
##   _perceive()  -> snapshot of fairly-observable state (positions, states,
##                   attack phases, cooldown pips, HP bars, live projectiles).
##                   Never reads hidden input or future actions.
##   _think()     -> every think tick, utility-score intents (advance, strafe,
##                   retreat, punish, wait/bait) and pick the best + noise.
##   _steer()     -> every frame, smooth analog movement toward the intent
##                   (no jitter/twitch), with arena-edge avoidance.
##   _offense()   -> distance + character-kit move choice, punish windows,
##                   short combos, human-like pacing (no spam/cancels).
##   _defense()   -> reaction-delayed dodges (dash i-frames) and knight
##                   counter-guard, with per-difficulty mistake rolls.
##
## The game has no jump button and no block button, so "dodging" = dash
## i-frames + spacing, and "guarding" = knight S1 counter stance + spacing.
## Difficulty changes behaviour/timing/consistency only, never damage/HP.

const DIFF_NAMES := ["Easy", "Normal", "Hard", "Expert"]
# react: s before a seen attack can be answered. think: decision interval.
# aggr/def/pun/combo: 0..1 tendencies. mist: chance to flub a defense read.
# maxc: longest combo. gap: min seconds between own attacks (anti-spam).
const DIFFS := [
	{"react": 0.38, "think": 0.16, "aggr": 0.35, "def": 0.25, "pun": 0.30,
		"combo": 0.12, "mist": 0.35, "maxc": 1, "gap": 0.95, "err": 0.60},
	{"react": 0.26, "think": 0.13, "aggr": 0.52, "def": 0.45, "pun": 0.55,
		"combo": 0.30, "mist": 0.20, "maxc": 2, "gap": 0.75, "err": 0.35},
	{"react": 0.17, "think": 0.11, "aggr": 0.66, "def": 0.66, "pun": 0.78,
		"combo": 0.50, "mist": 0.10, "maxc": 2, "gap": 0.60, "err": 0.20},
	{"react": 0.11, "think": 0.09, "aggr": 0.78, "def": 0.82, "pun": 0.92,
		"combo": 0.65, "mist": 0.04, "maxc": 3, "gap": 0.48, "err": 0.10},
]

const ARENA_R := 4.7
const EDGE_SOFT := 3.4

var game = null
var me = null
var foe = null
var diff := 1
var P: Dictionary = DIFFS[1]

# FSM / timers
var intent := "wait"
var intent_t := 0.0
var think_t := 0.0
var strafe_sign := 1.0
var orbit_t := 0.0
var next_atk_ok := 0.0
var defend_cd := 0.0
var pending_defend := -1.0 # game.now timestamp when a defense may trigger
var pending_kind := ""
var combo_step := 0
var combo_due := -1.0
var last_foe_hp := 100.0
var foe_was_atk := false
var cur := Vector2.ZERO # smoothed steering (world x/z)
var prefer_range := 2.0


func setup(p_game, p_me, p_foe, p_diff: int) -> void:
	game = p_game
	me = p_me
	foe = p_foe
	set_difficulty(p_diff)
	reset_ai()


func set_difficulty(i: int) -> void:
	diff = clampi(i, 0, DIFFS.size() - 1)
	P = DIFFS[diff]


func reset_ai() -> void:
	intent = "wait"
	intent_t = 0.0
	think_t = randf() * 0.1
	next_atk_ok = 0.0
	defend_cd = 0.0
	pending_defend = -1.0
	pending_kind = ""
	combo_step = 0
	combo_due = -1.0
	cur = Vector2.ZERO
	strafe_sign = 1.0 if randf() < 0.5 else -1.0
	orbit_t = randf_range(1.0, 2.5)
	foe_was_atk = false
	if me != null and game != null:
		last_foe_hp = 100.0
	_prefer_range()


func _is_knight() -> bool:
	return me != null and String(me.skin_name) == "cubeknight"


func _is_cowboy() -> bool:
	return me != null and String(me.skin_name) == "cubecowboy"


func _is_ninja() -> bool:
	return me != null and String(me.skin_name) == "ninja"


func _prefer_range() -> void:
	if _is_cowboy():
		prefer_range = 4.2
	elif _is_knight():
		prefer_range = 1.8
	elif _is_ninja():
		prefer_range = 2.6
	else:
		prefer_range = 2.1


func update(dt: float, play: bool) -> void:
	if game == null or me == null or foe == null:
		return
	if not me.ai_enabled:
		return
	if not play:
		me.ai_ix = 0.0
		me.ai_iy = 0.0
		return
	if String(me.st) == "ko" or String(foe.st) == "ko" or not (foe as Node3D).visible:
		_drift_center(dt)
		return
	_prefer_range()
	defend_cd = maxf(0.0, defend_cd - dt)
	intent_t -= dt
	orbit_t -= dt
	if orbit_t <= 0.0:
		orbit_t = randf_range(1.2, 3.0)
		if randf() < 0.6:
			strafe_sign = -strafe_sign
	think_t -= dt
	if think_t <= 0.0:
		think_t = float(P["think"])
		_think()
	_watch_foe_attacks()
	_fire_pending_defense()
	_fire_combo()
	_steer(dt)


# ---------- perception (only what a human could see) ----------

func _dist() -> float:
	var dx: float = foe.position.x - me.position.x
	var dz: float = foe.position.z - me.position.z
	return Vector2(dx, dz).length()


# Returns foe attack phase info from public state (windup/active/recover).
func _foe_phase() -> Dictionary:
	if String(foe.st) != "atk" or foe.atk == null:
		return {"active": false}
	var a: Dictionary = foe.atk
	var w := float(a.get("w", 0.3))
	var av := float(a.get("a", 0.2))
	var r := float(a.get("r", 0.3))
	var t: float = foe.t
	var ph := "windup"
	if t >= w + av:
		ph = "recover"
	elif t >= w:
		ph = "active"
	return {"active": true, "kind": String(a.get("kind", "")),
		"phase": ph, "t": t, "w": w, "a": av, "r": r,
		"range": float(a.get("range", 2.2)),
		"big": bool(a.get("big", false))}


func _foe_vulnerable() -> bool:
	if String(foe.st) == "stun":
		return true
	var f := _foe_phase()
	if not bool(f["active"]):
		return false
	# Punish window: active frames nearly over, or in recovery.
	return String(f["phase"]) == "recover" or (
		String(f["phase"]) == "active" and float(f["t"]) > float(f["w"]) + float(f["a"]) * 0.7)


func _foe_guarding() -> bool:
	return foe.counter_open() if foe.has_method("counter_open") else false


# ---------- think: utility-scored intent FSM ----------

func _think() -> void:
	var d := _dist()
	var f := _foe_phase()
	var foe_attacking := bool(f["active"])
	var vuln := _foe_vulnerable()
	var err: float = float(P["err"])
	var scores := {"advance": 0.0, "strafe": 0.0, "retreat": 0.0,
		"punish": 0.0, "wait": 0.0}
	# Base drives
	if d > prefer_range + 0.4:
		scores["advance"] = 1.2 + (d - prefer_range) * 0.25
	else:
		scores["strafe"] = 0.8
	if d < 1.0:
		scores["retreat"] = 0.6 # avoid body-push + give spacing
	# Punish a whiffed / recovering foe
	if vuln and float(foe.inv) <= 0.0 and d < 4.5:
		scores["punish"] = 1.6 * float(P["pun"]) + 0.6
	# Cowboy wants its gun range instead of face-hugging
	if _is_cowboy() and d < 2.4 and not vuln:
		scores["retreat"] = maxf(float(scores["retreat"]), 1.1)
	# Ninja plays mid-range hit-and-run: room to throw kunai, space to slash in
	if _is_ninja() and d < 1.6 and not vuln:
		scores["retreat"] = maxf(float(scores["retreat"]), 0.8)
	# Danger: foe winding up something big up close -> back off / evade
	if foe_attacking and String(f["phase"]) == "windup" and bool(f["big"]) and d < float(f["range"]) + 1.0:
		scores["retreat"] = maxf(float(scores["retreat"]), 0.9 + float(P["def"]))
	# Low HP: play safer, reset to neutral
	if float(me.hp) < 30.0 and d < 3.0:
		scores["retreat"] = float(scores["retreat"]) + 0.7
		scores["punish"] = float(scores["punish"]) * 0.6
	# Don't attack into an open knight counter: bait instead
	if _foe_guarding() and d < 2.6:
		scores["wait"] = 1.5
		scores["punish"] = 0.0
		scores["advance"] = 0.2
	# Occasional human-like patience: hold even in range
	if randf() > float(P["aggr"]) + 0.25 and d < prefer_range + 0.6 and not vuln:
		scores["wait"] = maxf(float(scores["wait"]), 0.9)
	# Strafe variety so movement isn't a straight line
	if intent == "advance" and randf() < 0.35:
		scores["strafe"] = float(scores["strafe"]) + 0.5
	# Pick best + unpredictability noise (scaled by difficulty error)
	var best := "wait"
	var best_v := -999.0
	for k in scores.keys():
		var v: float = float(scores[k]) + randf_range(-err, err) * 0.5
		if v > best_v:
			best_v = v
			best = String(k)
	_set_intent(best)
	_maybe_attack(d, vuln)


func _set_intent(n: String) -> void:
	if n != intent:
		intent = n
		if n == "strafe" and randf() < 0.4:
			strafe_sign = -strafe_sign
	intent_t = randf_range(0.35, 0.8)


# ---------- steering: smooth, edge-aware, no jitter ----------

func _desired_dir(d: float) -> Vector2:
	var to_foe := Vector2(foe.position.x - me.position.x, foe.position.z - me.position.z)
	if to_foe.length() < 0.001:
		to_foe = Vector2(1, 0)
	to_foe = to_foe.normalized()
	var want := Vector2.ZERO
	match intent:
		"advance":
			want = to_foe
			if d < prefer_range * 0.75:
				want = to_foe * 0.25 # arrive: don't shove into the player
		"punish":
			want = to_foe
		"retreat":
			want = -to_foe
		"strafe":
			want = Vector2(-to_foe.y, to_foe.x) * strafe_sign + to_foe * 0.35
			if want.length() > 0.01:
				want = want.normalized()
		_:
			# wait/bait: tiny drift to hold spacing, never full still (alive feel)
			if d > prefer_range + 0.5:
				want = to_foe * 0.4
			elif d < prefer_range - 0.7:
				want = -to_foe * 0.4
	# Arena edge avoidance: blend toward center near the rim
	var p := Vector2(me.position.x, me.position.z)
	var edge := clampf((p.length() - EDGE_SOFT) / maxf(ARENA_R - EDGE_SOFT, 0.01), 0.0, 1.0)
	if edge > 0.0:
		var to_center := -p.normalized() if p.length() > 0.01 else Vector2.ZERO
		want = (want * (1.0 - edge) + to_center * edge * 1.5)
		if want.length() > 1.0:
			want = want.normalized()
	return want


func _steer(dt: float) -> void:
	var d := _dist()
	var want := _desired_dir(d)
	var k := 1.0 - exp(-8.0 * dt) # smoothing: no twitchy direction flips
	cur = cur.lerp(want, k)
	if cur.length() < 0.08:
		cur = Vector2.ZERO
	elif cur.length() > 1.0:
		cur = cur.normalized()
	# Inverse of the fighter's isometric mapping
	# (wx = ix-iy, wz = -ix-iy  ->  ix = (wx-wz)/2, iy = -(wx+wz)/2)
	me.ai_ix = (cur.x - cur.y) * 0.5
	me.ai_iy = (-cur.x - cur.y) * 0.5


func _drift_center(dt: float) -> void:
	var p := Vector2(me.position.x, me.position.z)
	if p.length() > 0.5:
		var w := (-p.normalized()) * 0.5
		me.ai_ix = (w.x - w.y) * 0.5
		me.ai_iy = (-w.x - w.y) * 0.5
	else:
		me.ai_ix = 0.0
		me.ai_iy = 0.0


# ---------- offense: kits, punishes, combos, pacing ----------

func _can_act() -> bool:
	return String(me.st) == "free" and float(me.rec) <= 0.0


func _maybe_attack(d: float, vuln: bool) -> void:
	if not _can_act():
		return
	if game.now < next_atk_ok:
		return
	if _foe_guarding():
		return # never swing into an open counter
	if float(foe.inv) > 0.0:
		return
	var mv := _choose_move(d, vuln)
	if mv == "":
		return
	# Commit (goes through the same buffer/cooldown path as human input)
	me.ai_press(mv)
	next_atk_ok = game.now + float(P["gap"]) + randf_range(0.0, 0.3)
	combo_step = 0
	combo_due = -1.0


func _choose_move(d: float, vuln: bool) -> String:
	var aggr: float = float(P["aggr"])
	if _is_cowboy():
		return _cowboy_move(d, vuln, aggr)
	if _is_knight():
		return _knight_move(d, vuln, aggr)
	if _is_ninja():
		return _ninja_move(d, vuln, aggr)
	return _generic_move(d, vuln, aggr)


func _ready_spell(n: String) -> bool:
	return float(me.cd.get(n, 99.0)) <= 0.0


func _cowboy_move(d: float, vuln: bool, aggr: float) -> String:
	# Gunslinger: hold mid-range, fan-fire pressure, rifle punishes, rare horse ride.
	if d > 3.0:
		if _ready_spell("S2") and (vuln or randf() < aggr * 0.7):
			return "S2" # rifle: heavy ranged punish
		if _ready_spell("S1") and randf() < 0.35 + aggr * 0.5:
			return "S1" # fan-fire: 6-shot pressure
		if _ready_spell("S3") and d < 6.0 and randf() < 0.03 + aggr * 0.10:
			return "S3" # horse ride: occasional, not spam
		if d > 5.0 or randf() < aggr:
			return "H" if (vuln and d < 2.6) else ""
		return ""
	if d > 2.0:
		if _ready_spell("S1") and randf() < 0.4 + aggr * 0.4:
			return "S1"
		return "H" if randf() < aggr else "L"
	# Too close: jab out or (retreat intent handles spacing)
	return "L" if randf() < 0.7 else "H"


func _knight_move(d: float, vuln: bool, aggr: float) -> String:
	# Sword + shield: tight spacing, bash punishes, sweep mixups, counter is
	# defensive-only (fired from _fire_pending_defense, never here).
	if vuln and d < 2.8 and _ready_spell("S2"):
		return "S2" # shield bash: the punish tool
	if d < 1.7:
		if _ready_spell("S3") and randf() < 0.15 + aggr * 0.25:
			return "S3" # sword sweep mixup
		return "L" if randf() < 0.65 else "H"
	if d < 2.7:
		return "H" if randf() < 0.35 + aggr * 0.4 else "L"
	if d < 4.0 and _ready_spell("S2") and vuln:
		return "S2" # chase-down bash on a whiff
	return ""


func _ninja_move(d: float, vuln: bool, aggr: float) -> String:
	# Hit-and-run: kunai at range, katana dash-slash to punish or engage,
	# smoke bomb to cover mid-range, melee only up close.
	if d > 3.0:
		if _ready_spell("S2") and (vuln or randf() < aggr * 0.6):
			return "S2" # kunai throw
		if _ready_spell("S3") and d < 5.0 and randf() < 0.05 + aggr * 0.12:
			return "S3" # smoke bomb: zone control, not spam
		return ""
	if d > 2.0:
		if _ready_spell("S3") and vuln and randf() < 0.3 + aggr * 0.3:
			return "S3" # smoke on a recovering foe, then slash in
		if _ready_spell("S1") and randf() < 0.35 + aggr * 0.45:
			return "S1" # katana dash-slash engagement
		return "H" if randf() < aggr * 0.5 else ""
	if _ready_spell("S1") and (vuln or randf() < aggr * 0.4):
		return "S1"
	return "L" if randf() < 0.65 else "H"


func _generic_move(d: float, vuln: bool, aggr: float) -> String:
	if d > 3.2:
		if _ready_spell("S1") and (vuln or randf() < aggr * 0.6):
			return "S1" # dash attack: gap closer
		return ""
	if d > 1.6:
		if _ready_spell("S2") and randf() < 0.2 + aggr * 0.35:
			return "S2" # uppercut
		return "H" if randf() < 0.3 + aggr * 0.4 else "L"
	if _ready_spell("S3") and randf() < aggr * 0.25:
		return "S3" # spin, close-range mixup
	return "L" if randf() < 0.6 else "H"


# Combo follow-ups: only when the last hit visibly landed (foe HP dropped
# and foe is stunned), capped per difficulty, human-paced delay.
func _fire_combo() -> void:
	if combo_due < 0.0:
		# Detect a landed hit to start/extend a combo
		if float(foe.hp) < last_foe_hp - 0.01 and String(foe.st) == "stun":
			if combo_step < int(P["maxc"]) and randf() < float(P["combo"]):
				combo_due = game.now + randf_range(0.18, 0.32)
				combo_step += 1
		last_foe_hp = float(foe.hp)
		return
	if game.now < combo_due:
		last_foe_hp = float(foe.hp)
		return
	combo_due = -1.0
	last_foe_hp = float(foe.hp)
	if not _can_act() or float(foe.inv) > 0.0 or _foe_guarding():
		return
	var d := _dist()
	if d > 3.0:
		return # don't whiff the follow-up across the arena
	var mv := "L"
	if _is_knight() and d < 2.6 and _ready_spell("S2"):
		mv = "S2"
	elif _is_cowboy() and d >= 2.0 and _ready_spell("S1"):
		mv = "S1"
	elif _is_ninja() and d < 2.8 and _ready_spell("S1"):
		mv = "S1"
	elif d >= 1.6:
		mv = "H"
	me.ai_press(mv)
	next_atk_ok = game.now + float(P["gap"]) * 0.7


# ---------- defense: delayed, fallible, loop-safe ----------

# Rising-edge detection on foe attacks + incoming projectiles. Only the
# *start* of an attack is observed; the response fires after the difficulty's
# reaction delay, and may be deliberately flubbed (mistake roll).
func _watch_foe_attacks() -> void:
	var f := _foe_phase()
	var now_atk := bool(f["active"])
	if now_atk and not foe_was_atk:
		_on_foe_attack_started(f)
	foe_was_atk = now_atk
	# Live projectiles heading our way (fair: they are visible in the world)
	if game.bullets is Array:
		for b in game.bullets:
			if not (b is Dictionary):
				continue
			if b.get("owner") != foe:
				continue
			var bp: Vector3 = b.get("p", foe.position)
			var bv: Vector3 = b.get("v", Vector3.ZERO)
			var to_me: Vector3 = me.position - bp
			to_me.y = 0.0
			if to_me.length() > 4.5 or to_me.length() < 0.01:
				continue
			var dir := bv.normalized() if bv.length() > 0.01 else Vector3.ZERO
			if dir.dot(to_me.normalized()) > 0.86 and pending_defend < 0.0 and defend_cd <= 0.0:
				pending_defend = game.now + float(P["react"]) * 0.7
				pending_kind = "bullet"


func _on_foe_attack_started(f: Dictionary) -> void:
	if defend_cd > 0.0 or pending_defend >= 0.0:
		return
	var kind := String(f.get("kind", ""))
	if kind in ["fan", "rifle", "kunai", "smoke"]:
		return # shooter/zoner: answer with pressure, not retreat (intent logic)
	if _foe_guarding():
		return
	var d := _dist()
	var reach := float(f.get("range", 2.2)) + 1.3
	if kind in ["bash", "sweep"]:
		reach += 0.4
	if d > reach:
		return # not threatened; a human wouldn't flinch either
	if randf() < float(P["mist"]):
		return # deliberate mistake: eat it like a human would
	pending_defend = game.now + float(P["react"])
	pending_kind = kind


func _fire_pending_defense() -> void:
	if pending_defend < 0.0 or game.now < pending_defend:
		return
	pending_defend = -1.0
	var kind := pending_kind
	pending_kind = ""
	if not _can_act() or defend_cd > 0.0:
		return
	if randf() > float(P["def"]) + 0.25:
		return # chose to hold ground / was baited
	var d := _dist()
	# Knight answers melee with its shield counter when in range...
	if _is_knight() and kind != "bullet" and d < 2.5 and _ready_spell("S1") and randf() < 0.75:
		me.ai_press("S1")
		defend_cd = lerpf(2.0, 0.9, float(P["def"]))
		next_atk_ok = game.now + 0.5
		return
	# ...otherwise dash-dodge away/sideways (i-frames), steered, not random.
	var away := Vector2(me.position.x - foe.position.x, me.position.z - foe.position.z)
	if away.length() < 0.01:
		away = Vector2(1, 0)
	away = away.normalized()
	var side := Vector2(-away.y, away.x) * strafe_sign
	var dash_dir := (away * 0.8 + side * 0.6).normalized()
	# Don't dash off the platform: pull toward center near the rim
	var p := Vector2(me.position.x, me.position.z)
	if p.length() > EDGE_SOFT:
		dash_dir = ((dash_dir * 0.4 - p.normalized() * 0.6)).normalized()
	cur = dash_dir # steering follows through so the dash goes where intended
	me.ai_ix = (cur.x - cur.y) * 0.5
	me.ai_iy = (-cur.x - cur.y) * 0.5
	me.ai_press("D")
	defend_cd = lerpf(2.2, 1.0, float(P["def"]))
