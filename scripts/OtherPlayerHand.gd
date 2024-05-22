class_name OtherPlayerHand extends Node3D

@onready var ref_pivot = $"HandPivot"
@onready var ref_cardobject = preload("res://scenes/Card.tscn")

func DisplayHand(player: Player)-> void:
    var direction: bool = true
    var card_nb: int = 0

    $"Label3D".text = "<%s>" % player.username

    for card in player.hand:
        if direction:
            card_nb += 1

        var wrap_node: Node3D = Node3D.new()
        ref_pivot.add_child(wrap_node)

        var card_object: CardObject = ref_cardobject.instantiate()
        wrap_node.add_child(card_object)

        var fake_card = Card.new(0, GameRules.CardColor.SPECIAL, GameRules.CardEffect.NONE)
        card_object.Setup(fake_card)

        card_object.position.z = -1
        card_object.position.y = (card_nb if direction else 0 - card_nb) * 0.02
        card_object.position.x = (card_nb if direction else 0 - card_nb) * 0.2
        wrap_node.rotation.y = (0 - card_nb if direction else card_nb) * 0.05

        direction = not direction
