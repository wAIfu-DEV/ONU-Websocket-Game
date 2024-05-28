class_name WebsocketManager extends Node

const MAX_RECONNECT: int = 5
var WEBSOCKET_URL: String = ""

const DEFAULT_PROTOCOL_DATA_MESSAGE: Dictionary = {
        "version": 1,
        "type": "data",
        "from": "",
        "to": ["all"],
        "payload": {
            "name": "",
            "content": ""
        }
    }

const DEFAULT_PROTOCOL_TEXT_MESSAGE: Dictionary = {
        "version": 1,
        "type": "message",
        "from": "",
        "to": ["all"],
        "payload": {
            "name": "",
            "content": ""
        }
    }

const DATA_TYPE_PING: String = "onu-ping"
const DATA_TYPE_PONG: String = "onu-pong"
const DATA_TYPE_HASHOST: String = "onu-hashost"
const DATA_TYPE_ISHOST: String = "onu-ishost"
const DATA_TYPE_START: String = "onu-start"
const DATA_TYPE_TURN: String = "onu-turn"
const DATA_TYPE_WON: String = "onu-won"
const DATA_TYPE_PLAYERTURN: String = "onu-player-turn"
const DATA_TYPE_PLAYERACTION: String = "onu-player-action"
const DATA_TYPE_PLAYCARD_ANIM: String = "onu-play-anim"

var ws: WebSocketPeer = null
var ref_game: Game = null

var reconnect_amount: int = 0
var previously_connected: bool = false

signal connected

var uri = ""
var headers = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    ref_game = get_tree().current_scene

func _process(_delta: float)-> void:
    if reconnect_amount > MAX_RECONNECT: return
    if ws == null: return
    ws.poll()
    match ws.get_ready_state():
        WebSocketPeer.STATE_OPEN:
            if !previously_connected:
                print("CONNECTED.")
                connected.emit()
            previously_connected = true
            while ws.get_available_packet_count():
                HandleIncomingPacket(ws.get_packet())
        WebSocketPeer.STATE_CLOSED:
            print("CLOSED:", ws.get_close_code(), " ", ws.get_close_reason())
            previously_connected = false
            TryReconnect()
            reconnect_amount += 1


func ConnectToServer(url: String, user: String, password: String, room: String)-> Error:
    previously_connected = false
    reconnect_amount = 0

    # Encode credentials
    var credentials = "%s:%s" % [user, password]
    var encoded_credentials = Marshalls.utf8_to_base64(credentials)
    headers = ["Authorization: Basic %s" % encoded_credentials]

    # Formulate the WebSocket URI with credentials
    uri = "ws://%s@%s/%s" % [encoded_credentials, url, room]
    print("Connecting to URI:", uri)

    # Initiate the WebSocket connection
    ws = WebSocketPeer.new()
    ws.handshake_headers = headers
    var err = ws.connect_to_url(uri)
    if err != OK:
        print("Error connecting to WebSocket:", err)
    return err


func DisconnectFromServer()-> void:
    if ws == null: return
    print("Disconnected from server.")
    ws.close()
    ws = null


func TryReconnect()-> void:
    print("Trying reconnect...")
    var err = ws.connect_to_url(uri)
    if err == OK:
        reconnect_amount = 0
        print("Successfuly reconnected")
    else:
        print("Failed to reconnect")


func MakeProtocolMessage(payload_name: String, payload_content: String, to: Array[String] = ["all"])-> Dictionary:
    var msg: Dictionary = DEFAULT_PROTOCOL_DATA_MESSAGE.duplicate(true)
    msg["to"] = to
    msg["from"] = ref_game.ws_user
    msg["payload"]["name"] = payload_name
    msg["payload"]["content"] = payload_content
    return msg


func HandleIncomingPacket(packet: PackedByteArray)-> void:
    var payload: String = packet.get_string_from_utf8()
    var json: Dictionary = JSON.parse_string(payload)
    if json == null:
        printerr("Received unparsable payload from websocket.")
        return
    print("RECEIVED: ", json)
    if json["type"] != "data":
        return
    var to: Array = json["to"]
    if not ("all" in to or ref_game.ws_user in to):
        return
    var data_type = json["payload"]["name"]
    print("RECEIVED TYPE: ", data_type)
    var from = json["from"]
    match data_type:
        DATA_TYPE_PING:
            if from == ref_game.ws_user: return
            var player: Player = Player.new()
            player.is_user = false
            player.ws_user = from
            player.username = json["payload"]["content"]
            ref_game.AddPlayerInWaitingRoom(player)
            var msg = MakeProtocolMessage(DATA_TYPE_PONG, ref_game.player_name)
            SendMessage(msg)
        DATA_TYPE_PONG:
            var player: Player = Player.new()
            player.is_user = false
            player.ws_user = from
            player.username = json["payload"]["content"]
            ref_game.AddPlayerInWaitingRoom(player)
        DATA_TYPE_HASHOST:
            if !ref_game.is_host: return
            var msg = MakeProtocolMessage(DATA_TYPE_ISHOST, "")
            SendMessage(msg)
        DATA_TYPE_ISHOST:
            if from == ref_game.ws_user: return
            if ref_game.is_host:
                ref_game.SetGameMenu(Game.GameMenu.MAIN)
            ref_game.game_has_host = true
            ref_game.host_name = from
        DATA_TYPE_START:
            if ref_game.is_host: return
            print("Received start signal.")
            var json_state = JSON.parse_string(json["payload"]["content"])
            ref_game.GetStateFromJSON(json_state)
            ref_game.SetGameMenu(Game.GameMenu.NONE)
        DATA_TYPE_TURN:
            if ref_game.is_host: return
            if ref_game.is_waiting_for_turn_play: return
            var json_state = JSON.parse_string(json["payload"]["content"])
            ref_game.GetStateFromJSON(json_state)
        DATA_TYPE_PLAYERACTION:
            if !ref_game.is_host: return
            var player = ref_game.GetPlayerByWsUser(json["from"])
            var json_action = JSON.parse_string(json["payload"]["content"])
            var action = json_action["Action"]
            if action == GameRules.PlayAction.PICK_CARD:
                player.hand.push_back(ref_game.DrawFromDeck())
                ref_game.ReflectGameState()
                await get_tree().create_timer(1.0).timeout
                var player_turn_state: Dictionary = ref_game.GetPlayerTurnInfosJSON(player)
                var msg = MakeProtocolMessage(DATA_TYPE_PLAYERTURN, JSON.stringify(player_turn_state), [player.ws_user])
                SendMessage(msg)
                var turn_state: Dictionary = ref_game.GetPlayerTurnInfosJSON(player)
                var turn_msg = MakeProtocolMessage(DATA_TYPE_TURN, JSON.stringify(turn_state), [player.ws_user])
                SendMessage(turn_msg)
                return
            ref_game.card_played.emit(json_action["CardIndex"], json_action["WildColor"])
        DATA_TYPE_WON:
            if ref_game.is_host: return
            ref_game.GameWon(json["payload"]["content"])
        DATA_TYPE_PLAYCARD_ANIM:
            if ref_game.is_host: return
            var json_action = JSON.parse_string(json["payload"]["content"])
            var anim_from = json_action["AnimFrom"]
            var card = Card.FromJSON(json_action["Card"])
            ref_game.CardPlayAnimation(ref_game.GetPlayerByWsUser(anim_from), card)


func SendString(packet: String)-> void:
    if ws == null: return
    if ws.get_ready_state() != ws.STATE_OPEN:
        printerr("Tried to send from closed websocket.")
        return
    print("SENT: ", packet)
    ws.send_text(packet)


func SendMessage(msg: Dictionary)-> void:
    if ws == null: return
    if ws.get_ready_state() != ws.STATE_OPEN:
        printerr("Tried to send from closed websocket.")
        return
    print("SENT: ", msg)
    print("SENT TYPE: ", msg["payload"]["name"])
    ws.send_text(JSON.stringify(msg))
