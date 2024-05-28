# ONU (Websocket Collab Protocol Game)
## How to implement
### Flow Chart
1. Receive player turn data.
2. Process data.
3. React to data using the ai vtuber (or not).
4. Send back the result.
### Data You Receive
If you are unaware of the format of WCP messages, please refer to: [https://github.com/wAIfu-DEV/WebsocketCollabClient?tab=readme-ov-file#format-of-json-messages](https://github.com/wAIfu-DEV/WebsocketCollabClient?tab=readme-ov-file#format-of-json-messages)

The player turn data will be sent in a `data` message with the payload label `onu-player-turn`

The data itself will be a stringified JSON string in `payload.content`

The parsed data will look like this:
```js
{
    "TurnDirection": "Right", /* or "Left" */
    "TopStackCard": Card,
    "HandCards": [], /* Array of Card */
    "PlayerHands": [], /* Array of PlayerHand */
    "PlayerOrder": [] /* Array of player names (string) ordered by turn (assuming right turn) */
}
```
**Enums**:
```gdscript
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
```
**Card**:
```js
{
    "Color": CardColor,
    "Number": Number, /* Number on card, is -1 if is an effect card. Is in range -1 to 9 inclusive */
    "Effect": CardEffect
}
```
**PlayerHand**:
```js
{
    "Name": String, /* Name of the player */
    "CardCount": Number /* Number of cards in the player's hand */
}
```
### Data You Send
Once you are finished processing the data, here are is the data you will send back to the server:
```js
{
    "Action": PlayAction, /* PlayAction.PLAY_CARD if you can play a card,
    or PlayAction.PICK_CARD if you cannot play with the current hand */
    "CardIndex": Number, /* Index of the Card you want to play */
    "WildColor": CardColor, /* Color to switch to when playing a Wild Card */
}
```
In order to send the data back to the server, you need to create a `data` message with the payload label `onu-player-action`.

The data itself should then be stringified and set as the payload content.

### Considerations
Due to the way ONU works, you will want to receive messages that might be sent *by* you (for example if you are the host).

Since messages sent by the user are discarded by the `onDataMessage` listener, it is necessary to use the `onAllMessages` to receive the necessary data.

### JavaScript Example
```js
const WebsocketCollabClient = require("./wcc");

/** @typedef { {sender: string, content: string, trusted: boolean} } Message */

const WS_URL = "<URL>";
const USER = "<USER>";
const PASS = "<PASS>";
const CHANNEL_ID = "<CHANNEL>";

/** @type { WebsocketCollabClient? } */
let wcc = null;

/** @param { any } passed_logger */
exports.onLoad = (passed_logger) => {
    logger = passed_logger;
    logger.print("Loaded Collab plugin.");

    wcc = new WebsocketCollabClient();

    wcc.connect(WS_URL, CHANNEL_ID, {
        user: USER,
        pass: PASS,
    })
        .then(() => {
            logger.print("Initialized WCC ONU.");

            wcc.onAllMessages = (json) => {
                logger.print("JSON:", json);

                let to_you = json["to"].includes(USER) || json["to"].includes("all");
                let data_label = json["payload"]["name"];
                let data_content = json["payload"]["content"];

                if (to_you && data_label == "onu-player-turn") {
                    logger.print("Received turn data.");
                    playTurn(data_content, json);
                    return;
                }
            };
        })
        .catch((reason) => {
            logger.warn("Could not connect to server:", reason);
        });
};

exports.onQuit = () => {
    if (wcc) wcc.disconnect();
    wcc = null;
};

/** @typedef { {Color: number, Number: number, Effect: number} } Card */
/** @typedef { {Name: string, CardCount: number} } PlayerHand */
/** @typedef { {TurnDirection: string, TopStackCard: Card, HandCards: Card[], PlayerHands: PlayerHand[], PlayerOrder: string[]} } TurnInfo */

/** @typedef { {CardIndex: number, Weight: number} } WeightedCardPick */

const CardEffect = {
    NONE: 0,
    REVERSE: 1,
    SKIP_TURN: 2,
    PICK_2: 3,
    WILD_CARD: 4,
    WILD_PICK_4: 5,
};

const CardColor = {
    BLUE: 0,
    RED: 1,
    YELLOW: 2,
    GREEN: 3,
    SPECIAL: 4,
};

const PlayAction = {
    PLAY_CARD: 0,
    PICK_CARD: 1,
};

/**
 * Play the turn.
 * @param { string } data_string
 * @param { any } message
 * @returns
 */
function playTurn(data_string, message) {
    if (typeof data_string != "string") {
        logger.warn("Received data of unknown type.");
        return;
    }

    let json;
    try {
        json = JSON.parse(data_string);
    } catch {
        logger.warn("Could not parse data from onu.");
        return;
    }

    /** @type { TurnInfo } */
    let data = json;

    let host_name = message["from"];
    let stack_card = data.TopStackCard;

    let optimal_color = getOptimalColor(data.HandCards);
    let picked_card = pickCardIndex(data.HandCards, stack_card, optimal_color);

    let action_data = JSON.stringify({
        Action: picked_card == null ? PlayAction.PICK_CARD : PlayAction.PLAY_CARD,
        CardIndex: picked_card,
        WildColor: optimal_color,
    });

    wcc.sendData("onu-player-action", action_data);
}

/**
 * @param { Card[] } cards
 * @returns { number }
 */
function getOptimalColor(cards) {
    let color_count = {};
    color_count[CardColor.BLUE] = 0;
    color_count[CardColor.RED] = 0;
    color_count[CardColor.YELLOW] = 0;
    color_count[CardColor.GREEN] = 0;

    let optimal_color = CardColor.BLUE;

    for (let i = 0; i < cards.length; ++i) {
        let card = cards[i];
        if (card.Color == CardColor.SPECIAL) continue;
        if (++color_count[card.Color] > color_count[optimal_color])
            optimal_color = card.Color;
    }
    return optimal_color;
}

/**
 * @param { Card[] } cards
 * @param { Card } stack_card
 * @returns { number? }
 */
function pickCardIndex(cards, stack_card, optimal_color) {
    /** @type { WeightedCardPick[] } */
    let picked_cards = [];

    for (let i = 0; i < cards.length; ++i) {
        let card = cards[i];
        let base_weight = 0.0;

        if (card.Effect != CardEffect.NONE) {
            base_weight += 0.5;
        }

        if (card.Color == optimal_color) {
            base_weight += 0.25;
        }

        if (card.Color == CardColor.SPECIAL) {
            picked_cards.push({
                CardIndex: i,
                Weight: 1.0 + base_weight,
            });
            continue;
        }

        if (
            card.Effect != CardEffect.NONE &&
            card.Effect == stack_card.Effect
        ) {
            picked_cards.push({
                CardIndex: i,
                Weight: 0.75 + base_weight,
            });
            continue;
        }

        if (card.Color == stack_card.Color) {
            picked_cards.push({
                CardIndex: i,
                Weight: 0.5 + base_weight,
            });
            continue;
        }

        if (card.Number == stack_card.Number && card.Number >= 0) {
            picked_cards.push({
                CardIndex: i,
                Weight: 0.5 + base_weight,
            });
            continue;
        }
    }

    if (!picked_cards.length) return null;

    picked_cards.sort((a, b) => b.Weight - a.Weight);
    return picked_cards[0].CardIndex;
}
```
