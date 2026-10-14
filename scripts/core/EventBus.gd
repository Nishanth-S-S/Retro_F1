extends Node
## Global signal hub. Systems talk through here instead of holding references to each other.

signal money_changed(amount: int)
signal research_changed(amount: int)
signal setup_changed
signal part_installed(slot: String, part_id: String)
signal part_removed(slot: String)
signal inventory_changed
signal settings_changed
signal driver_message(text: String, color: Color)
signal lap_completed(car: Node, lap_time: float, valid: bool)
signal sector_completed(car: Node, sector: int, sector_time: float)
signal race_state_changed(state: String)
signal tooltip_requested(term: String)
