class_name Card extends Node

var color: GameRules.CardColor = GameRules.CardColor.SPECIAL
var number: int = 0
var effect: GameRules.CardEffect = GameRules.CardEffect.NONE

func _init(_number: int, _color: GameRules.CardColor, _effect: GameRules.CardEffect) -> void:
    number = _number
    color = _color
    effect = _effect
