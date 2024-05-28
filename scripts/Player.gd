class_name Player extends Node

var is_user: bool = false
var username: String = "player"
var ws_user: String = ""
var hand: Array[Card] = []

func ToJSON()-> Dictionary:
    var cards = []
    for card in hand:
        cards.push_back(card.ToJSON())
    return {
        "DisplayName": username,
        "UserName": ws_user,
        "Cards": cards
    }

static func FromJSON(dict: Dictionary, player_name: String)-> Player:
    var player: Player = Player.new()
    if dict["UserName"] == player_name:
        player.is_user = true
    player.username = dict["DisplayName"]
    player.ws_user = dict["UserName"]
    for json_card in dict["Cards"]:
        player.hand.push_back(Card.FromJSON(json_card))
    return player

