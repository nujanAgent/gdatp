extends Node3D
## A painted sky with sun, moon, stars and clouds, the lights that follow them, fog that matches the horizon, and shadows.
## Use:
##   var sky = preload("res://parts/sky.gd").new()
##   sky.mood = "sunset"            # day, sunset, dawn, night, overcast, alien: a look that stays
##   sky.cycle_seconds = 480.0      # or a full day and night in this many seconds; 0 keeps the mood
##   sky.fog_near = 46.0            # fog starts here and is solid at fog_far; lower them to hide a small world's edge
##   sky.fog_far = 84.0
##   add_child(sky)
##   sky.clock_text()               # "14:30"
##   sky.daylight()                 # from 0 at night to 1 at noon
## Looks its best with the mobile or forward renderer; compatibility gets a plain graded sky with a sun, and no clouds or stars.
## Set your own colours by giving moods a new entry before add_child: sky.moods["mars"] = [zenith, horizon, sun, sun energy, ambient energy, ambient tint].

const SKY_SHADER := """
shader_type sky;

uniform vec3 zenith : source_color;
uniform vec3 horizon : source_color;
uniform vec3 sun_tint : source_color;
uniform vec3 sun_direction;
uniform float night = 0.0;
uniform float cloud_light = 1.0;
uniform float cloud_cover = 0.54;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, -0.2, 1.0);
	vec3 color = mix(horizon, zenith, pow(clamp(up * 1.25, 0.0, 1.0), 0.55));
	if (d.y < 0.0) {
		color = mix(horizon, horizon * 0.62, clamp(-d.y * 5.0, 0.0, 1.0));
	}
	float to_sun = dot(d, sun_direction);
	color += sun_tint * pow(max(to_sun, 0.0), 26.0) * 0.32;
	color += sun_tint * smoothstep(0.9975, 0.9988, to_sun) * 2.4;
	float to_moon = dot(d, -sun_direction);
	color += vec3(0.82, 0.86, 0.98) * smoothstep(0.9982, 0.9990, to_moon) * night * 1.6;
	if (night > 0.01 && d.y > 0.0) {
		vec2 grid = d.xz / max(d.y + 0.3, 0.1) * 95.0;
		float star = step(0.9965, hash(floor(grid)));
		float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + hash(floor(grid) + 3.0) * 40.0);
		color += vec3(star * twinkle) * night * smoothstep(0.0, 0.25, d.y);
	}
	if (d.y > 0.015) {
		vec2 p = d.xz / (d.y + 0.14) * 1.5 + vec2(TIME * 0.012, 0.0);
		float clouds = noise(p) * 0.55 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.15;
		clouds = smoothstep(cloud_cover, cloud_cover + 0.2, clouds) * smoothstep(0.015, 0.2, d.y);
		color = mix(color, vec3(1.0, 0.98, 0.95) * cloud_light, clouds * 0.82);
	}
	COLOR = color;
}
"""

## Colour through a day: time, zenith, horizon, sun tint, sun energy, ambient energy, ambient tint.
const DAY := [
	[0.00, "0a1030", "141c3e", "9fb0e0", 0.00, 0.26, "7f90c8"],
	[0.21, "0a1030", "1c2448", "9fb0e0", 0.00, 0.28, "7f90c8"],
	[0.27, "3b5a9a", "f09a5e", "ffb066", 0.55, 0.42, "e8b48f"],
	[0.34, "4f8fe0", "bfdcf0", "fff0d0", 0.95, 0.52, "dfe8f5"],
	[0.50, "3f86e8", "c4e2f6", "fffbe8", 1.05, 0.56, "e8f0fa"],
	[0.68, "4f8fe0", "c8ddee", "fff0d0", 0.95, 0.52, "dfe8f5"],
	[0.75, "3a4f8c", "f2885a", "ff9a58", 0.5, 0.42, "e8a68a"],
	[0.81, "0d1436", "27285a", "9fb0e0", 0.00, 0.28, "7f90c8"],
	[1.00, "0a1030", "141c3e", "9fb0e0", 0.00, 0.26, "7f90c8"],
]

## Each mood: zenith, horizon, sun tint, sun energy, ambient energy, ambient tint, time of day for the sun's place, cloud cover.
var moods := {
	"day": ["3f86e8", "c4e2f6", "fffbe8", 1.05, 0.56, "e8f0fa", 0.42, 0.54],
	"sunset": ["34407e", "f2885a", "ff9a58", 0.8, 0.46, "e8a68a", 0.72, 0.5],
	"dawn": ["4a6aa8", "f4b48a", "ffc08a", 0.7, 0.46, "eac0a8", 0.28, 0.58],
	"night": ["0a1030", "1c2448", "9fb0e0", 0.0, 0.3, "7f90c8", 0.98, 0.6],
	"overcast": ["6f7c8c", "aeb6bf", "dfe3e8", 0.35, 0.72, "c8d0d8", 0.42, 0.34],
	"alien": ["2a1248", "d0507a", "ffd080", 0.85, 0.5, "c090c0", 0.6, 0.5],
}
var mood := "day"
var cycle_seconds := 0.0
var fog_near := 46.0
var fog_far := 84.0
var time_of_day := 0.34
var environment: Environment
var sun: DirectionalLight3D

var _moon: DirectionalLight3D
var _painted: ShaderMaterial
var _plain: ProceduralSkyMaterial
## The compatibility renderer lights a surface more brightly than the others for the same energy.
var _light_scale := 1.0


func _ready() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		_light_scale = 0.56
	var dome := Sky.new()
	if _light_scale < 1.0:
		_plain = ProceduralSkyMaterial.new()
		dome.sky_material = _plain
	else:
		var shader := Shader.new()
		shader.code = SKY_SHADER
		_painted = ShaderMaterial.new()
		_painted.shader = shader
		dome.sky_material = _painted
	dome.radiance_size = Sky.RADIANCE_SIZE_64
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = dome
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.4
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = fog_near
	environment.fog_depth_end = fog_far
	environment.fog_sun_scatter = 0.0
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	var holder := WorldEnvironment.new()
	holder.environment = environment
	add_child(holder)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 44.0
	sun.shadow_opacity = 0.72
	sun.shadow_blur = 1.4
	add_child(sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color("8fa2dc")
	_moon.light_energy = 0.0
	add_child(_moon)
	if cycle_seconds <= 0.0:
		_apply_mood()
		set_process(false)
	else:
		_apply_day()


func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / cycle_seconds, 1.0)
	_apply_day()


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]


func daylight() -> float:
	return clampf(sun.light_energy / _light_scale, 0.0, 1.0)


func _apply_mood() -> void:
	var chosen: Array = moods.get(mood, moods["day"])
	time_of_day = chosen[6]
	if _painted != null:
		_painted.set_shader_parameter("cloud_cover", chosen[7])
	_show(Color(chosen[0]), Color(chosen[1]), Color(chosen[2]), chosen[3], chosen[4], Color(chosen[5]))


func _apply_day() -> void:
	var a: Array = DAY[0]
	var b: Array = DAY[1]
	for i in DAY.size() - 1:
		if time_of_day >= DAY[i][0] and time_of_day <= DAY[i + 1][0]:
			a = DAY[i]
			b = DAY[i + 1]
			break
	var t := inverse_lerp(float(a[0]), float(b[0]), time_of_day)
	_show(Color(a[1]).lerp(Color(b[1]), t), Color(a[2]).lerp(Color(b[2]), t), Color(a[3]).lerp(Color(b[3]), t), lerpf(a[4], b[4], t), lerpf(a[5], b[5], t), Color(a[6]).lerp(Color(b[6]), t))


func _show(zenith: Color, horizon: Color, tint: Color, energy: float, ambient: float, ambient_tint: Color) -> void:
	var angle := (time_of_day - 0.25) * TAU
	var sun_way := Vector3(cos(angle), sin(angle), 0.35).normalized()
	var night := clampf(1.0 - energy * 2.2, 0.0, 1.0)
	if _painted != null:
		_painted.set_shader_parameter("zenith", zenith)
		_painted.set_shader_parameter("horizon", horizon)
		_painted.set_shader_parameter("sun_tint", tint)
		_painted.set_shader_parameter("sun_direction", sun_way)
		_painted.set_shader_parameter("night", night)
		_painted.set_shader_parameter("cloud_light", lerpf(0.16, 1.0, clampf(energy, 0.0, 1.0)))
	else:
		_plain.sky_top_color = zenith
		_plain.sky_horizon_color = horizon
		_plain.ground_horizon_color = horizon
		_plain.ground_bottom_color = horizon.darkened(0.4)
	environment.ambient_light_color = ambient_tint
	environment.ambient_light_energy = ambient * _light_scale
	environment.fog_light_color = horizon
	if sun_way.y > 0.0:
		sun.look_at_from_position(sun_way, Vector3.ZERO, Vector3.UP)
	sun.light_color = tint
	sun.light_energy = energy * _light_scale
	sun.visible = energy > 0.01
	if sun_way.y < 0.0:
		_moon.look_at_from_position(-sun_way, Vector3.ZERO, Vector3.UP)
	_moon.light_energy = night * 0.32
	_moon.visible = night > 0.02
