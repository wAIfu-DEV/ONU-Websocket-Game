class_name Game extends Node

enum GameMenu { NONE, MAIN, OPTIONS, WAITROOM, USERINFOPROMPT }
var back_menu: GameMenu = GameMenu.MAIN

@onready var ref_other_player = preload("res://scenes/OtherPlayerHand.tscn")

var player_name: String = "player"
var ws_user: String = ""
var ws_pass: String = ""
var ws_room: String = ""

const MAX_PLAYERS: int = 8
const STARTING_CARDS_AMOUNT: int = 7

var players: Array[Player] = []
var deck: Array[Card] = []
var played_cards_stack: Array[Card] = []

var current_direction: bool = true
var current_player_idx: int = 0

var current_turn_effect: GameRules.CardEffect = GameRules.CardEffect.NONE

func _ready() -> void:
    players.push_back(Player.new())
    players[0].is_user = true
    players.push_back(Player.new())
    players.push_back(Player.new())
    players.push_back(Player.new())
    players.push_back(Player.new())
    players.push_back(Player.new())
    players.push_back(Player.new())
    FillCardDeck()
    players[0].hand.append_array(DrawMultipleFromDeck(7))
    players[1].hand.append_array(DrawMultipleFromDeck(7))
    players[2].hand.append_array(DrawMultipleFromDeck(7))
    players[3].hand.append_array(DrawMultipleFromDeck(7))
    players[4].hand.append_array(DrawMultipleFromDeck(7))
    players[5].hand.append_array(DrawMultipleFromDeck(7))
    players[6].hand.append_array(DrawMultipleFromDeck(7))
    $"PlayedStack/CardObject".Setup(Card.new(8, GameRules.CardColor.BLUE, GameRules.CardEffect.REVERSE))
    DisplayHand(players[0])
    SpawnOtherPlayers()

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("ui_cancel"):
        SetGameMenu(back_menu)


func DisplayUserInfoPrompt()-> void:
    $"UserInfoPrompt".visible = true


func EnterWaitRoom()-> void:
    pass


func sort_random(_a, _b):
    return true if randf() > 0.5 else false


func FillCardDeck()-> void:
    for color_i in range(4):
        deck.push_back(Card.new(0, color_i as GameRules.CardColor, GameRules.CardEffect.NONE))

        for number_card_i in range(8):
            deck.push_back(Card.new(number_card_i + 1, color_i as GameRules.CardColor, GameRules.CardEffect.NONE))

        for action_i in range(1):
            deck.push_back(Card.new(-1, color_i as GameRules.CardColor, GameRules.CardEffect.REVERSE))
            deck.push_back(Card.new(-1, color_i as GameRules.CardColor, GameRules.CardEffect.SKIP_TURN))
            deck.push_back(Card.new(-1, color_i as GameRules.CardColor, GameRules.CardEffect.PICK_2))

    for special_i in range(3):
        deck.push_back(Card.new(-1, GameRules.CardColor.SPECIAL, GameRules.CardEffect.WILD_CARD))
        deck.push_back(Card.new(-1, GameRules.CardColor.SPECIAL, GameRules.CardEffect.WILD_PICK_4))

    ShuffleDeck()


func ShuffleDeck()-> void:
    deck.sort_custom(sort_random)


func RefillDeckFromStack()-> void:
    while played_cards_stack.size() > 1:
        deck.push_back(played_cards_stack.pop_front())
    ShuffleDeck()


func DrawFromDeck()-> Card:
    if deck.size() <= 0:
        RefillDeckFromStack()
    return deck.pop_back()


func DrawMultipleFromDeck(amount: int)-> Array[Card]:
    var result: Array[Card] = []
    for card_i in range(amount - 1):
        result.push_back(DrawFromDeck())
    return result


func DealStartingCards()-> void:
    for player_i in range(players.size()):
        var cards = DrawMultipleFromDeck(7)
        players[player_i].hand.append_array(cards)


func StartGame()-> void:
    FillCardDeck()
    DealStartingCards()
    played_cards_stack.push_back(DrawFromDeck())

    while true:
        pass


func NextPlayer()-> void:
    if current_turn_effect == GameRules.CardEffect.REVERSE:
        current_direction = not current_direction

    if current_direction:
        current_player_idx += 1
        if current_player_idx >= MAX_PLAYERS:
            current_player_idx = 0
    else:
        current_player_idx -= 1
        if current_player_idx < 0:
            current_player_idx = MAX_PLAYERS - 1


func ResetCardEffect()-> void:
    current_turn_effect = GameRules.CardEffect.NONE


func PickCard()-> int:
    return 0


func GetStackCard()-> Card:
    return played_cards_stack.back()


func CanPlayCard(card: Card)-> bool:
    if card.color == GameRules.CardColor.SPECIAL:
        return true

    var stack_card = GetStackCard()
    if card.color == stack_card.color:
        return true
    if card.number == stack_card.number:
        return true
    return false


func PlayCard(player: Player, card: Card)-> void:
    player.hand.erase(card)
    current_turn_effect = card.effect


func ApplyEffect(player: Player)-> bool:
    match current_turn_effect:
        GameRules.CardEffect.SKIP_TURN:
            return true
        GameRules.CardEffect.PICK_2:
            var cards: Array[Card] = DrawMultipleFromDeck(2)
            player.hand.append_array(cards)
            return false
        GameRules.CardEffect.WILD_PICK_4:
            var cards: Array[Card] = DrawMultipleFromDeck(4)
            player.hand.append_array(cards)
            return false
        _:
            return false


func PickNewStackColor()-> void:
    pass


func PlayTurn()-> void:
    var player: Player = players[current_player_idx]

    var skip: bool = ApplyEffect(player)
    ResetCardEffect()

    if skip:
        NextPlayer()
        return

    var picked_card_idx: int = PickCard()
    var card: Card = player.hand[picked_card_idx]

    while not CanPlayCard(card):
        picked_card_idx = PickCard()
        card = player.hand[picked_card_idx]

    PlayCard(player, card)

    if card.color == GameRules.CardColor.SPECIAL:
        PickNewStackColor()
    NextPlayer()


func DisplayHand(player: Player)-> void:
    $"PlayerHand".DisplayHand(player)


func SpawnOtherPlayers()-> void:
    var deg_per_player: float = 360.0 / float(players.size())

    var player_i: int = 0
    for player in players:
        if player.is_user: continue
        player_i += 1
        var other_player: OtherPlayerHand = ref_other_player.instantiate()
        $"OtherPlayers".add_child(other_player)
        other_player.rotation_degrees.y = deg_per_player * player_i
        other_player.DisplayHand(player)


func SetGameMenu(menu: GameMenu)-> void:
    var menus = [
        $"MainMenu",
        $"UserInfoPrompt",
        $"WaitRoom",
    ]

    match menu:
        GameMenu.NONE:
            $"MenuBackground".visible = false
            for m in menus:
                m.visible = false
            back_menu = GameMenu.NONE
        GameMenu.MAIN:
            $"MenuBackground".visible = true
            for m in menus:
                m.visible = false
            $"MainMenu".visible = true
            back_menu = GameMenu.MAIN
        GameMenu.OPTIONS:
            $"MenuBackground".visible = true
            for m in menus:
                m.visible = false
            back_menu = GameMenu.MAIN
        GameMenu.WAITROOM:
            $"MenuBackground".visible = true
            for m in menus:
                m.visible = false
            $"WaitRoom".visible = true
            back_menu = GameMenu.USERINFOPROMPT
        GameMenu.USERINFOPROMPT:
            $"MenuBackground".visible = true
            for m in menus:
                m.visible = false
            $"UserInfoPrompt".visible = true
            back_menu = GameMenu.MAIN


func _on_join_button_pressed() -> void:
    SetGameMenu(GameMenu.USERINFOPROMPT)

func _on_quit_button_pressed() -> void:
    get_tree().quit()

func _on_continue_button_pressed() -> void:
    assert(false, "NOT IMPLEMENTED")
