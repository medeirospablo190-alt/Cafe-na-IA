extends Node3D
# Mundo CAFEÍNA integrado ao APK. Mapa de 11 objetos derivado das dimensões
# do mundo validado; a antiga GDExtension Luau e o anti-cheat AINDA NÃO rodam aqui.

const SPEED: float = 4.1
const JUMP_SPEED: float = 5.0
const GRAVITY: float = 15.0
const SPAWN: Vector3 = Vector3(0.0, 0.86, 4.2)

var player: CharacterBody3D
var camera: Camera3D
var move_axis: Vector2 = Vector2.ZERO
var move_touch_id: int = -1
var look_touch_id: int = -1
var joystick_center: Vector2 = Vector2.ZERO
var jump_requested: bool = false
var joystick_knob: ColorRect
var joystick_base: ColorRect
var jump_button: Button
var reset_button: Button
var hud_status: Label

const BLOCKS := [
    ["Chao", Vector3(0, -0.15, 0), Vector3(10, 0.3, 16), Color(0.21, 0.30, 0.39), true],
    ["ParedeEsquerda", Vector3(-3.25, 1.65, 0), Vector3(2.5, 3.3, 0.62), Color(0.94, 0.31, 0.29), true],
    ["ParedeDireita", Vector3(3.25, 1.65, 0), Vector3(2.5, 3.3, 0.62), Color(0.94, 0.31, 0.29), true],
    ["PortaEvento", Vector3(0, 1.65, 0), Vector3(4.0, 3.3, 0.62), Color(0.29, 0.68, 1.0), true],
    ["LinhaDeInicio", Vector3(0, 0.02, 3.1), Vector3(5.8, 0.035, 0.14), Color(0.27, 0.68, 1.0), false],
    ["ZonaVerde", Vector3(0, 0.02, -4.2), Vector3(3.1, 0.035, 2.0), Color(0.23, 0.85, 0.43), false],
    ["ObstaculoBaixo", Vector3(-2.55, 0.37, 2.05), Vector3(1.55, 0.74, 0.58), Color(0.98, 0.76, 0.29), true],
    ["PlataformaAzul", Vector3(2.45, 2.55, 1.55), Vector3(1.7, 0.22, 1.65), Color(0.29, 0.56, 1.0), true],
    ["MarcadorAltura", Vector3(3.8, 2.75, 1.55), Vector3(0.12, 5.5, 0.12), Color(0.30, 0.82, 0.92), false],
    ["ZonaPorta", Vector3(0, 0.025, 1.45), Vector3(4.4, 0.04, 1.25), Color(0.20, 0.67, 1.0), false],
    ["ZonaGravidade", Vector3(2.45, 0.025, -2.45), Vector3(1.7, 0.04, 2.2), Color(1.0, 0.79, 0.23), false]
]

func _ready() -> void:
    # The native editor stays portrait; only the embedded world uses landscape.
    DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
    _create_lighting()
    for entry in BLOCKS:
        _create_block(entry[0], entry[1], entry[2], entry[3], entry[4])
    _create_player()
    _create_mobile_ui()
    get_viewport().size_changed.connect(_layout_mobile_ui)
    _layout_mobile_ui()

func _create_lighting() -> void:
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-52, -28, 0)
    light.light_energy = 1.5
    add_child(light)
    var env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.06, 0.09, 0.15)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.58, 0.66, 0.78)
    environment.ambient_light_energy = 0.7
    env.environment = environment
    add_child(env)

func _create_block(block_name: String, where: Vector3, dimensions: Vector3,
        tint: Color, solid: bool) -> void:
    var root: Node3D
    if solid:
        var body := StaticBody3D.new()
        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = dimensions
        collision.shape = shape
        body.add_child(collision)
        root = body
    else:
        root = Node3D.new()
    root.name = block_name
    root.position = where
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = dimensions
    mesh.mesh = box
    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    mesh.material_override = material
    root.add_child(mesh)
    add_child(root)

func _create_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Personagem"
    player.position = SPAWN
    player.floor_snap_length = 0.22
    var collision := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.34
    capsule.height = 1.65
    collision.shape = capsule
    player.add_child(collision)
    var mesh := MeshInstance3D.new()
    var model := CapsuleMesh.new()
    model.radius = 0.34
    model.height = 1.65
    mesh.mesh = model
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.25, 0.82, 0.95)
    mesh.material_override = material
    player.add_child(mesh)
    camera = Camera3D.new()
    camera.position = Vector3(0, 2.6, 5.0)
    camera.rotation_degrees.x = -16
    camera.current = true
    player.add_child(camera)
    add_child(player)

func _create_mobile_ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)
    var overlay := Control.new()
    overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(overlay)
    var screen := get_viewport().get_visible_rect().size

    hud_status = Label.new()
    hud_status.position = Vector2(24, 16)
    hud_status.add_theme_font_size_override("font_size", 22)
    hud_status.add_theme_color_override("font_color", Color.WHITE)
    hud_status.text = "CAFEÍNA  |  MUNDO 3D  •  11 blocos  •  gravidade 15"
    overlay.add_child(hud_status)

    var help := Label.new()
    help.position = Vector2(24, 52)
    help.add_theme_font_size_override("font_size", 15)
    help.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
    help.text = "Controle esquerdo: andar   •   arraste à direita: câmera"
    overlay.add_child(help)

    var base := ColorRect.new()
    base.color = Color(0.13, 0.35, 0.65, 0.38)
    base.size = Vector2(132, 132)
    base.position = Vector2(26, screen.y - 158)
    base.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(base)
    joystick_base = base
    joystick_center = base.position + Vector2(66, 66)
    joystick_knob = ColorRect.new()
    joystick_knob.color = Color(0.69, 0.88, 1.0, 0.72)
    joystick_knob.size = Vector2(48, 48)
    joystick_knob.position = joystick_center - joystick_knob.size / 2.0
    joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(joystick_knob)

    var jump := Button.new()
    jump.text = "PULAR"
    jump.position = Vector2(screen.x - 170, screen.y - 118)
    jump.size = Vector2(145, 86)
    jump.add_theme_font_size_override("font_size", 22)
    jump.pressed.connect(func() -> void: jump_requested = true)
    overlay.add_child(jump)
    jump_button = jump

    var reset := Button.new()
    reset.text = "REINICIAR PERSONAGEM"
    reset.position = Vector2(screen.x - 245, 17)
    reset.size = Vector2(225, 52)
    reset.pressed.connect(_reset_player)
    overlay.add_child(reset)
    reset_button = reset

func _layout_mobile_ui() -> void:
    if not is_instance_valid(joystick_base):
        return
    var screen := get_viewport().get_visible_rect().size
    joystick_base.position = Vector2(26, screen.y - 158)
    joystick_center = joystick_base.position + Vector2(66, 66)
    joystick_knob.position = joystick_center + move_axis * 53.0 - joystick_knob.size / 2.0
    jump_button.position = Vector2(screen.x - 170, screen.y - 118)
    reset_button.position = Vector2(screen.x - 245, 17)

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        var screen := get_viewport().get_visible_rect().size
        if touch.pressed:
            if touch.position.x < screen.x * 0.43 and touch.position.y > screen.y * 0.48:
                if move_touch_id == -1:
                    move_touch_id = touch.index
                    _update_joystick(touch.position)
            elif touch.position.x > screen.x * 0.43 and touch.position.y < screen.y * 0.76:
                if look_touch_id == -1:
                    look_touch_id = touch.index
        else:
            if touch.index == move_touch_id:
                move_touch_id = -1
                move_axis = Vector2.ZERO
                _update_joystick(joystick_center)
            if touch.index == look_touch_id:
                look_touch_id = -1
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if drag.index == move_touch_id:
            _update_joystick(drag.position)
        elif drag.index == look_touch_id:
            player.rotation.y -= drag.relative.x * 0.0038
            camera.rotation.x = clampf(camera.rotation.x - drag.relative.y * 0.0028, -0.65, 0.3)

func _update_joystick(position: Vector2) -> void:
    var offset := (position - joystick_center).limit_length(53)
    move_axis = offset / 53.0
    joystick_knob.position = joystick_center + offset - joystick_knob.size / 2.0

func _physics_process(delta: float) -> void:
    if not is_instance_valid(player):
        return
    var key_axis := Vector2.ZERO
    if Input.is_key_pressed(KEY_A):
        key_axis.x -= 1
    if Input.is_key_pressed(KEY_D):
        key_axis.x += 1
    if Input.is_key_pressed(KEY_W):
        key_axis.y -= 1
    if Input.is_key_pressed(KEY_S):
        key_axis.y += 1
    var input_axis := (move_axis + key_axis).limit_length(1.0)
    var direction := Vector3(input_axis.x, 0, input_axis.y)
    direction = direction.rotated(Vector3.UP, player.rotation.y)
    player.velocity.x = direction.x * SPEED
    player.velocity.z = direction.z * SPEED
    if player.is_on_floor():
        if jump_requested or Input.is_key_pressed(KEY_SPACE):
            player.velocity.y = JUMP_SPEED
        elif player.velocity.y < 0:
            player.velocity.y = -0.1
    else:
        player.velocity.y -= GRAVITY * delta
    jump_requested = false
    player.move_and_slide()
    if player.position.y < -12:
        _reset_player()

func _reset_player() -> void:
    player.global_position = SPAWN
    player.velocity = Vector3.ZERO
    move_axis = Vector2.ZERO
    move_touch_id = -1
    look_touch_id = -1
    _update_joystick(joystick_center)
