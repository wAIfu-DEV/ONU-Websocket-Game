class_name GameRules extends Node

enum CardEffect {
    NONE = 0,
    REVERSE = 1,
    SKIP_TURN = 2,
    PICK_2 = 3,
    WILD_CARD = 4,
    WILD_PICK_4 = 5
}

enum CardColor {
    BLUE = 0,
    RED = 1,
    YELLOW = 2,
    GREEN = 3,
    SPECIAL = 4
}

enum PlayAction {
    PLAY_CARD = 0,
    PICK_CARD = 1
}
