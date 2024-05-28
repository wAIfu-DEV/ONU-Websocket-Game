# ONU (Websocket Collab Protocol Game)
## How to implement
### Flow Chart
1. Receive player turn data.
2. Process data.
3. React to data using the ai vtuber (or not).
4. Send back the result.
### Received Data
If you are unaware of the format of WCP messages, please refer to: [https://github.com/wAIfu-DEV/WebsocketCollabClient?tab=readme-ov-file#format-of-json-messages](https://github.com/wAIfu-DEV/WebsocketCollabClient?tab=readme-ov-file#format-of-json-messages)

The player turn data will be sent in a `data` message with the payload label `onu-player-action`

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
```
**Card**:
```js
{
    "Color": CardColor,
    "Number": -1 -> 9, /* Number on card, is -1 if is an effect card */
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
