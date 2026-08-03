class_name SellPopup
extends CanvasLayer
## SellPopup: dive summary shown when cargo is sold at the surface —
## per-ore breakdown, total $, and any ether earned. The "reward moment"
## of the core loop.

signal dismissed


func _init(total_money: int, total_ether: int, breakdown: Dictionary) -> void:
	layer = 22
	var content := UIKit.modal(self, "ORES SOLD")
	for ore_id: String in breakdown:
		var ore: Dictionary = Balance.ores[ore_id]
		var count := int(breakdown[ore_id])
		var row := UIKit.hbox(12)
		var name_label := UIKit.label("%s x%d" % [ore["name"], count], 26)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UIKit.label("%d $" % (int(ore["value"]) * count), 26, UIKit.GOOD))
		content.add_child(row)
	var total := UIKit.label("Total: %d $" % total_money, 36, UIKit.GOOD)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(total)
	if total_ether > 0:
		var ether_label := UIKit.label("+%d ether" % total_ether, 28, UIKit.ETHER)
		ether_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(ether_label)
	var btn := UIKit.button("NICE!", 30, true)
	btn.pressed.connect(func() -> void:
		dismissed.emit()
		queue_free())
	content.add_child(btn)
