class_name Game extends Node

var CRED_FILE_PATH = OS.get_user_data_dir() + "\\onu_user.json"

enum GameMenu { NONE, MAIN, OPTIONS, WAITROOM, WAITSCREEN, USERINFOPROMPT, CREDITS }
var current_menu: GameMenu = GameMenu.MAIN
var back_menu: GameMenu = GameMenu.MAIN

@onready var ref_other_player = preload("res://scenes/OtherPlayerHand.tscn")
@onready var websocket_manager: WebsocketManager = $"WebsocketManager"
@onready var template_row: PanelContainer = $"WaitRoom/VBoxContainer/PanelContainer"

var is_host: bool = false
var is_waiting_for_turn_play: bool = false
var game_has_host: bool = false
var host_name: String = ""

var player_name: String = "player"
var ws_user: String = ""
var ws_pass: String = ""
var ws_room: String = ""

const MAX_PLAYERS: int = 8
const STARTING_CARDS_AMOUNT: int = 7

var game_nb: int = 0

var players: Array[Player] = []
var deck: Array[Card] = []
var played_cards_stack: Array[Card] = []

var current_direction: bool = true
var current_player_idx: int = 0

var current_turn_effect: GameRules.CardEffect = GameRules.CardEffect.NONE

signal card_played(card_index: int, wild_color: int)

func _ready() -> void:
    LoadCredsFromFile()
    players.push_back(Player.new())
    players[0].is_user = true

func _process(_delta: float) -> void:
    if Input.is_action_just_pressed("ui_cancel"):
        if current_menu == GameMenu.WAITSCREEN: return
        if back_menu == GameMenu.USERINFOPROMPT:
            websocket_manager.DisconnectFromServer()
        if current_menu == GameMenu.NONE:
            game_nb += 1
            websocket_manager.DisconnectFromServer()
        SetGameMenu(back_menu)


func DisplayUserInfoPrompt()-> void:
    $"UserInfoPrompt".visible = true


func FillCardDeck()-> void:
    deck.clear()

    print("Filling card deck...")
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
    var n = deck.size()
    for i in range(n - 1, 0, -1):
        var j = randi() % (i + 1)
        var temp = deck[i]
        deck[i] = deck[j]
        deck[j] = temp


func RefillDeckFromStack()-> void:
    while played_cards_stack.size() > 1:
        var stack_card: Card = played_cards_stack.pop_front() as Card
        if stack_card.effect == GameRules.CardEffect.WILD_CARD or stack_card.effect == GameRules.CardEffect.WILD_PICK_4:
            stack_card.color = GameRules.CardColor.SPECIAL
        deck.push_back(stack_card)
    ShuffleDeck()


func DrawFromDeck()-> Card:
    if deck.size() <= 0:
        RefillDeckFromStack()
    return deck.pop_back()


func DrawMultipleFromDeck(amount: int)-> Array[Card]:
    var result: Array[Card] = []
    for card_i in range(0, amount):
        result.push_back(DrawFromDeck())
    return result


func DealStartingCards()-> void:
    print("Dealing starting cards...")
    for player in players:
        player.hand.clear()
        var cards = DrawMultipleFromDeck(7)
        for card in cards:
            player.hand.push_back(card)


func ReflectGameState(turn_name = null)-> void:
    $"PlayedStack/CardObject".Setup(played_cards_stack.back())
    DisplayHand(GetUserPlayer())
    SpawnOtherPlayers(turn_name)


func StartGame()-> void:
    SetGameMenu(Game.GameMenu.NONE)

    game_nb += 1
    var current_game_nb = game_nb

    FillCardDeck()
    DealStartingCards()
    played_cards_stack.push_back(DrawFromDeck())

    ReflectGameState()

    var json_state = JSON.stringify(StateToJSON())
    var msg = websocket_manager.MakeProtocolMessage(websocket_manager.DATA_TYPE_START, json_state)
    websocket_manager.SendMessage(msg)

    var previous_player: Player = null
    while not IsGameWon():
        if current_game_nb != game_nb: return
        await get_tree().create_timer(2).timeout
        if current_game_nb != game_nb: return
        print("Turn start.")
        var next_player = players[current_player_idx]
        await PlayTurn(next_player.username, current_game_nb)
        if current_game_nb != game_nb: return
        SendTurnData(next_player)
        ReflectGameState()
        previous_player = players[current_player_idx]
        NextPlayer()
        print("Turn end.")

    print("Game is won.")
    var wonmsg = websocket_manager.MakeProtocolMessage(websocket_manager.DATA_TYPE_WON, previous_player.username)
    websocket_manager.SendMessage(wonmsg)
    GameWon(previous_player.username)


func GameWon(winner_name: String)-> void:
    SetGameMenu(GameMenu.WAITSCREEN)
    game_nb += 1
    SetWaitScreenText("%s won the game." % winner_name)
    await get_tree().create_timer(3).timeout
    websocket_manager.DisconnectFromServer()
    SetGameMenu(GameMenu.MAIN)


func NextPlayer()-> void:
    if current_turn_effect == GameRules.CardEffect.REVERSE:
        current_direction = not current_direction

    if current_direction:
        current_player_idx += 1
        if current_player_idx >= players.size():
            current_player_idx = 0
    else:
        current_player_idx -= 1
        if current_player_idx < 0:
            current_player_idx = players.size() - 1


func ResetCardEffect()-> void:
    current_turn_effect = GameRules.CardEffect.NONE


func GetStackCard()-> Card:
    return played_cards_stack.back()


func CanPlayCard(card: Card)-> bool:
    if card.color == GameRules.CardColor.SPECIAL:
        return true

    var stack_card = GetStackCard()
    if card.effect == stack_card.effect:
        return true
    if card.color == stack_card.color:
        return true
    if card.number == stack_card.number && card.number >= 0:
        return true
    return false


func PlayCard(player: Player, card: Card)-> void:
    print("Played card:", card.ToJSON())
    played_cards_stack.push_back(card)
    player.hand.erase(card)
    current_turn_effect = card.effect


func ApplyEffect(player: Player)-> bool:
    match current_turn_effect:
        GameRules.CardEffect.SKIP_TURN:
            return true
        GameRules.CardEffect.PICK_2:
            var cards: Array[Card] = DrawMultipleFromDeck(2)
            player.hand.append_array(cards)
            print(player.username, " picked 2 cards.")
            return false
        GameRules.CardEffect.WILD_PICK_4:
            var cards: Array[Card] = DrawMultipleFromDeck(4)
            player.hand.append_array(cards)
            print(player.username, " picked 4 cards.")
            return false
        _:
            return false


func PickNewStackColor(new_color: int)-> void:
    played_cards_stack.back().color = new_color


func PlayTurn(playername: String, current_game_nb: int)-> void:
    if current_game_nb != game_nb: return
    var player: Player = GetPlayerByName(playername)

    var skip: bool = ApplyEffect(player)
    ResetCardEffect()

    if skip:
        print(player.username, "'s turn got skipped.")
        NextPlayer()
        return

    ReflectGameState()

    print("Waiting for ", player.username, "'s action.")

    var card: Card = null
    var picked_card_idx: int = 0
    var picked_color: int = 0

    if current_game_nb != game_nb: return

    while true:
        var turn_state: Dictionary = GetPlayerTurnInfosJSON(player)
        var msg = websocket_manager.MakeProtocolMessage(websocket_manager.DATA_TYPE_PLAYERTURN, JSON.stringify(turn_state), [player.ws_user])
        websocket_manager.SendMessage(msg)

        var play_result = await card_played
        print("Received play data")

        if current_game_nb != game_nb: return

        picked_card_idx = play_result[0]
        picked_color = play_result[1]
        assert(picked_card_idx < player.hand.size(), "Played card index %s is outside the bounds of the playable cards: %s\n%s" % [picked_card_idx, player.hand.size(), turn_state["HandCards"].size()])

        card = player.hand[picked_card_idx]

        if CanPlayCard(card):
            print("Can play selected card")
            break

        assert(false, "Could not play the provided card.")
        await get_tree().create_timer(1.0).timeout
        websocket_manager.SendMessage(msg)

    if current_game_nb != game_nb: return

    SendAnimData(player, card)
    await CardPlayAnimation(player, card)

    if current_game_nb != game_nb: return

    PlayCard(player, card)

    if card.color == GameRules.CardColor.SPECIAL:
        PickNewStackColor(picked_color)


func SendAnimData(player: Player, card: Card)-> void:
    var anim_data = JSON.stringify({
        "AnimFrom": player.ws_user,
        "Card": card.ToJSON()
    })
    var new_msg = websocket_manager.MakeProtocolMessage(websocket_manager.DATA_TYPE_PLAYCARD_ANIM, anim_data)
    websocket_manager.SendMessage(new_msg)


func SendTurnData(player: Player)-> void:
    var new_state = StateToJSON()
    new_state["PlayerTurn"] = player.username
    var new_json_state = JSON.stringify(new_state)
    var new_msg = websocket_manager.MakeProtocolMessage(websocket_manager.DATA_TYPE_TURN, new_json_state)
    websocket_manager.SendMessage(new_msg)


func IsGameWon()-> bool:
    for pl in players:
        if pl.hand.size() <= 0:
            print(pl.username, " has won.")
            return true
    return false


func DisplayHand(player: Player)-> void:
    $"PlayerHand".DisplayHand(player)


func CardPlayAnimation(player: Player, card: Card)-> void:
    if player.is_user:
        await $"PlayerHand".CardPlayAnimation(card)
    else:
        var ref_otherplayers = $"OtherPlayers"
        for child in ref_otherplayers.get_children():
            var playerhand: OtherPlayerHand = child as OtherPlayerHand
            if playerhand.username == player.username:
                await playerhand.CardPlayAnimation(card)
                return


func SpawnOtherPlayers(turn_name = null)-> void:
    var deg_per_player: float = 360.0 / float(players.size())

    var ref_otherplayers = $"OtherPlayers"
    while ref_otherplayers.get_child_count() > 0:
        ref_otherplayers.remove_child(ref_otherplayers.get_child(0))

    # doing this to have an array of players in order that starts with the user
    var before = []
    var after = []

    for pl in players:
        if pl.is_user: break
        before.push_back(pl)

    var found_player = false
    for pl in players:
        if found_player:
            after.push_back(pl)
            continue
        if pl.is_user:
            found_player = true

    var ordered_players = []
    ordered_players.append_array(before)
    ordered_players.append_array(after)

    var json_players = []
    for pl in ordered_players:
        json_players.push_back(pl.ToJSON())
    print(json_players)

    var player_i: int = 0
    for player in ordered_players:
        player_i += 1
        var other_player: OtherPlayerHand = ref_other_player.instantiate()
        ref_otherplayers.add_child(other_player)
        other_player.rotation_degrees.y = deg_per_player * player_i
        other_player.DisplayHand(player)
        if player.username == turn_name:
            other_player.SetPlaying(player)
        else:
            other_player.UnsetPlaying(player)


func SetGameMenu(menu: GameMenu)-> void:
    var menus = [
        $"MainMenu",
        $"UserInfoPrompt",
        $"WaitRoom",
        $"WaitScreen",
        $"Credits",
        $"Options"
    ]

    for m in menus:
        m.visible = false

    current_menu = menu
    match menu:
        GameMenu.NONE:
            $"MenuBackground".visible = false
            back_menu = GameMenu.MAIN
        GameMenu.MAIN:
            $"MenuBackground".visible = true
            $"MainMenu".visible = true
            back_menu = GameMenu.MAIN
        GameMenu.OPTIONS:
            $"MenuBackground".visible = true
            $"Options".visible = true
            back_menu = GameMenu.MAIN
        GameMenu.WAITROOM:
            ClearWaitRoom()
            $"MenuBackground".visible = true
            $"WaitRoom".visible = true
            back_menu = GameMenu.MAIN
        GameMenu.WAITSCREEN:
            $"MenuBackground".visible = true
            $"WaitScreen".visible = true
            back_menu = GameMenu.MAIN
        GameMenu.USERINFOPROMPT:
            $"MenuBackground".visible = true
            $"UserInfoPrompt".visible = true
            back_menu = GameMenu.MAIN
        GameMenu.CREDITS:
            $"MenuBackground".visible = true
            $"Credits".visible = true
            back_menu = GameMenu.MAIN


func AddPlayerInWaitingRoom(player: Player)-> void:
    if current_menu != GameMenu.WAITROOM: return

    for pl in players:
        if pl.ws_user == player.ws_user: return

    var row = template_row.duplicate()
    row.get_child(0).text = player.username
    $"WaitRoom/VBoxContainer".add_child(row)
    players.push_back(player)


func CheckRoomHasHost()-> bool:
    game_has_host = false
    var msg = websocket_manager.MakeProtocolMessage(websocket_manager.DATA_TYPE_HASHOST, "")
    websocket_manager.SendMessage(msg)
    await get_tree().create_timer(3).timeout
    return game_has_host or is_host


func SetWaitScreenText(text: String)-> void:
    $"WaitScreen/Label".text = text


func ClearWaitRoom()-> void:
    var ref_vbox = $"WaitRoom/VBoxContainer"
    while ref_vbox.get_child_count() > 1:
        ref_vbox.remove_child(ref_vbox.get_child(ref_vbox.get_child_count() - 1))


func StateToJSON()-> Dictionary:
    var json_players = []
    for pl in players:
        json_players.push_back(pl.ToJSON())

    var json_deck = []
    for card in deck:
        json_deck.push_back(card.ToJSON())

    var json_stack = []
    for card in played_cards_stack:
        json_stack.push_back(card.ToJSON())

    return {
        "Host": host_name,
        "Players": json_players,
        "Deck": json_deck,
        "Stack": json_stack,
        "Direction": "Right" if current_direction else "Left",
        "TurnEffect": current_turn_effect,
        "PlayerTurn": player_name,
    }


func GetStateFromJSON(dict: Dictionary)-> void:
    var player_turn: String = dict["PlayerTurn"]

    deck.clear()
    for json_card in dict["Deck"]:
        deck.push_back(Card.FromJSON(json_card))

    played_cards_stack.clear()
    for json_card in dict["Stack"]:
        played_cards_stack.push_back(Card.FromJSON(json_card))

    $"PlayedStack/CardObject".Setup(played_cards_stack.back())

    players.clear()
    for json_player in dict["Players"]:
        var player = Player.FromJSON(json_player, ws_user)
        if player.ws_user == ws_user:
            player.is_user = true
        players.push_back(player)

    ReflectGameState(player_turn)

    current_direction = dict["Direction"] == "Right"
    current_turn_effect = dict["TurnEffect"] as GameRules.CardEffect


func GetPlayerTurnInfosJSON(player: Player)-> Dictionary:
    var json_hand: Array[Dictionary] = []
    for card in player.hand:
        json_hand.push_back(card.ToJSON())

    var json_player_order: Array[String] = []
    var json_player_card_counts: Array[Dictionary] = []
    for pl in players:
        json_player_order.push_back(pl.username)
        json_player_card_counts.push_back({
            "Name": pl.username,
            "CardCount": pl.hand.size()
        })

    var top_stack_card: Card = played_cards_stack.back() as Card

    return {
        "TurnDirection": "Right" if current_direction else "Left",
        "TopStackCard": top_stack_card.ToJSON(),
        "HandCards": json_hand,
        "PlayerHands": json_player_card_counts,
        "PlayerOrder": json_player_order
    }


func GetPlayerByName(pl_name: String)-> Player:
    for pl in players:
        if pl.username == pl_name:
            return pl
    return null


func GetPlayerByWsUser(ws_username: String)-> Player:
    for pl in players:
        if pl.ws_user == ws_username:
            return pl
    return null


func GetUserPlayer()-> Player:
    for pl in players:
        if pl.is_user:
            return pl
    return null


func LoadCredsFromFile()-> void:
    if not FileAccess.file_exists(CRED_FILE_PATH): return
    var str = FileAccess.get_file_as_string(CRED_FILE_PATH)
    var dict = JSON.parse_string(str)
    var ref_url = $"UserInfoPrompt/UrlLine"
    ref_url.text = dict["WsUrl"]
    var ref_name = $"UserInfoPrompt/NameLine"
    ref_name.text = dict["UserName"]
    var ref_user = $"UserInfoPrompt/UserLine"
    ref_user.text = dict["WsUser"]
    var ref_pass = $"UserInfoPrompt/PassLine"
    ref_pass.text = dict["WsPass"]
    var ref_room = $"UserInfoPrompt/RoomLine"
    ref_room.text = dict["WsRoom"]


func WriteCredsToFile()-> void:
    var dict: Dictionary = {
        "UserName": player_name,
        "WsUser": ws_user,
        "WsPass": ws_pass,
        "WsRoom": ws_room,
        "WsUrl": websocket_manager.WEBSOCKET_URL
    }
    var f = FileAccess.open(CRED_FILE_PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(dict))
    f.close()


func _on_host_button_pressed() -> void:
    is_host = true
    SetGameMenu(GameMenu.USERINFOPROMPT)

func _on_join_button_pressed() -> void:
    is_host = false
    SetGameMenu(GameMenu.USERINFOPROMPT)

func _on_quit_button_pressed() -> void:
    get_tree().quit()

func _on_continue_button_pressed() -> void:
    var ref_url = $"UserInfoPrompt/UrlLine"
    websocket_manager.WEBSOCKET_URL = ref_url.text
    var ref_name = $"UserInfoPrompt/NameLine"
    player_name = ref_name.text
    var ref_user = $"UserInfoPrompt/UserLine"
    ws_user = ref_user.text
    var ref_pass = $"UserInfoPrompt/PassLine"
    ws_pass = ref_pass.text
    var ref_room = $"UserInfoPrompt/RoomLine"
    ws_room = ref_room.text

    WriteCredsToFile()

    var connect_err: Error = websocket_manager.ConnectToServer(websocket_manager.WEBSOCKET_URL, ws_user, ws_pass, ws_room)

    if connect_err:
        $"UserInfoPrompt/WarnLabel".visible = true
        return

    SetGameMenu(GameMenu.WAITSCREEN)
    SetWaitScreenText("Connecting...")
    await websocket_manager.connected

    SetWaitScreenText("Checking for Host..." if is_host else "Waiting for Host...")
    var has_host = await CheckRoomHasHost()

    if not has_host:
        SetWaitScreenText("Could not find Host.")
        await get_tree().create_timer(3).timeout
        websocket_manager.DisconnectFromServer()
        SetGameMenu(GameMenu.MAIN)
        return

    while players.size() > 1:
        players.pop_back()

    players[0].username = player_name
    players[0].ws_user = ws_user

    if is_host:
        host_name = ws_user

    $"WaitRoom/StartButton".visible = is_host

    SetGameMenu(GameMenu.WAITROOM)
    var msg = websocket_manager.MakeProtocolMessage(websocket_manager.DATA_TYPE_PING, player_name, [host_name])
    websocket_manager.SendMessage(msg)
    template_row.get_child(0).text = player_name

func _on_start_button_pressed() -> void:
    print("Started game.")
    StartGame()
    print("Ended game.")


func _on_credits_button_pressed() -> void:
    SetGameMenu(GameMenu.CREDITS)

func _on_options_button_pressed() -> void:
    SetGameMenu(GameMenu.OPTIONS)

func _on_h_slider_value_changed(value: float) -> void:
    if value <= 0.0:
        $"AudioStreamPlayer2D".volume_db = -80.0
        return
    $"AudioStreamPlayer2D".volume_db = -40.0 * (1.0 - value)
