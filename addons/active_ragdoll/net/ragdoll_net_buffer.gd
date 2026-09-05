class_name RagdollNetBuffer
extends RefCounted

const MAX_STATES := 32

var states: Array[RagdollNetState] = []


func push(state: RagdollNetState) -> void:
	if not states.is_empty() and state.time <= states[-1].time:
		return
	states.append(state)
	while states.size() > MAX_STATES:
		states.pop_front()


func latest() -> RagdollNetState:
	return null if states.is_empty() else states[-1]


func sample(time: float) -> RagdollNetState:
	if states.is_empty():
		return null
	if time >= states[-1].time:
		return states[-1]
	if time <= states[0].time:
		return states[0]
	for i in range(states.size() - 1, 0, -1):
		var older := states[i - 1]
		var newer := states[i]
		if time >= older.time and time <= newer.time:
			var span := newer.time - older.time
			return RagdollNetState.blend(older, newer, 0.0 if span <= 0.0 else (time - older.time) / span)
	return states[-1]


func clear() -> void:
	states.clear()
