class_name CardObject extends Node3D

@onready var ref_label: Label = $"RigidBody3D/SubViewport/Control/MainNumber"
@onready var ref_altlabel: Label = $"RigidBody3D/SubViewport/Control/AltNumber"
@onready var ref_color: ColorRect = $"RigidBody3D/SubViewport/Control/ColorRect"

var card: Card = null

func SetCardColor()-> void:
    match card.color:
        GameRules.CardColor.SPECIAL:
            ref_color.color = Color.BLACK
        GameRules.CardColor.RED:
            ref_color.color = Color.RED
        GameRules.CardColor.BLUE:
            ref_color.color = Color.BLUE
        GameRules.CardColor.GREEN:
            ref_color.color = Color.GREEN
        GameRules.CardColor.YELLOW:
            ref_color.color = Color.YELLOW


func SetCardText()-> void:
    if card.effect == GameRules.CardEffect.NONE:
        ref_label.text = String.num_int64(card.number)
        ref_altlabel.text = String.num_int64(card.number)
    else:
        match card.effect:
            GameRules.CardEffect.REVERSE:
                ref_label.text = "<>"
                ref_altlabel.text = "<>"
            GameRules.CardEffect.WILD_CARD:
                ref_label.text = "#"
                ref_altlabel.text = "#"
            GameRules.CardEffect.SKIP_TURN:
                ref_label.text = "<-"
                ref_altlabel.text = "<-"
            GameRules.CardEffect.PICK_2:
                ref_label.text = "+2"
                ref_altlabel.text = "+2"
            GameRules.CardEffect.WILD_PICK_4:
                ref_label.text = "+4"
                ref_altlabel.text = "+4"


func Setup(_card: Card)-> void:
    card = _card
    SetCardColor()
    SetCardText()
