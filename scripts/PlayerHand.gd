class_name PlayerHand extends Node3D

const MOVE_SPEED = 2.0
const DEFAULT_PIVOT_X_ROT = 43.2

@onready var ref_pivot = $"HandPivot"
@onready var ref_cardobject = preload("res://scenes/Card.tscn")
@onready var ref_pathfollow: PathFollow3D = $"Path3D/PathFollow3D" as PathFollow3D
@onready var ref_move_pivot: Node3D = $"Path3D/PathFollow3D/Node3D" as Node3D

var move_card: bool = false
signal finished_moving

func _process(delta: float) -> void:
    if move_card:
        var prog_amount = delta * MOVE_SPEED
        if ref_pathfollow.progress_ratio + prog_amount >= 1.0:
            ref_move_pivot.rotation_degrees.x = 0.0
            ref_pathfollow.progress_ratio = 1.0
            finished_moving.emit()
            return
        ref_pathfollow.progress_ratio += prog_amount
        ref_move_pivot.rotation_degrees.x = (1.0 - ref_pathfollow.progress_ratio) * DEFAULT_PIVOT_X_ROT

func DisplayHand(player: Player)-> void:
    while ref_pivot.get_child_count() > 0:
        ref_pivot.remove_child(ref_pivot.get_child(0))

    var direction: bool = false
    var card_nb: int = 0

    for card in player.hand:
        if direction:
            card_nb += 1

        var wrap_node: Node3D = Node3D.new()
        ref_pivot.add_child(wrap_node)

        var card_object: CardObject = ref_cardobject.instantiate()
        wrap_node.add_child(card_object)

        card_object.Setup(card)

        card_object.position.z = -1
        card_object.position.y = (card_nb if direction else 0 - card_nb) * 0.02
        card_object.position.x = (card_nb if direction else 0 - card_nb) * 0.2
        wrap_node.rotation.y = (0 - card_nb if direction else card_nb) * 0.05

        direction = not direction

func CardPlayAnimation(card: Card)-> void:
    var card_object: CardObject = ref_cardobject.instantiate()

    while ref_move_pivot.get_child_count() > 0:
        ref_move_pivot.remove_child(ref_move_pivot.get_child(0))

    ref_move_pivot.add_child(card_object)
    card_object.Setup(card)

    ref_pathfollow.progress_ratio = 0.0
    move_card = true
    await finished_moving
    ref_move_pivot.remove_child(ref_move_pivot.get_child(0))
