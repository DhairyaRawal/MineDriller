class_name BustScreen
extends CanvasLayer
## BustScreen: shown when a run ends badly (overheat, hull loss, government
## capture). States the GDD penalty clearly — cargo lost, money kept — and
## returns the player to the surface.

signal respawn_requested


## Losing a run is the moment a child decides whether to keep playing, so the
## copy is deliberately warm: name what happened, say plainly what was and was
## not lost (uncertainty is what actually stings), and offer one concrete thing
## to try next time. No "YOU FAILED", no blame.
const TIPS := [
	"Tip: drill in short bursts and let the drill cool between them.",
	"Tip: water pockets cool your drill instantly. Aim for the blue!",
	"Tip: the deeper you go, the less of the heat bar you can use.",
	"Tip: carve a ramp on the way down and you can run straight back up it.",
	"Tip: Magma Slugs cook your drill from a distance. Do not linger near one.",
]


func _init(reason: String) -> void:
	layer = 25
	var content := UIKit.modal(self, "RESCUED!")

	var reason_label := UIKit.wrapped(reason, 21)
	reason_label.custom_minimum_size = Vector2(460, 0)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(reason_label)

	var penalty := UIKit.label(
		"You lost the ore you were carrying,\nbut your money and upgrades are all safe.",
		17, UIKit.TEXT_DIM)
	penalty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(penalty)

	var tip := UIKit.wrapped(TIPS[randi() % TIPS.size()], 16, UIKit.ETHER)
	tip.custom_minimum_size = Vector2(460, 0)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tip)

	var btn := UIKit.action_button("TRY AGAIN")
	btn.pressed.connect(func() -> void:
		respawn_requested.emit()
		queue_free())
	content.add_child(btn)
