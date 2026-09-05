class_name RagdollNetClock
extends RefCounted

var offset: float = 0.0
var jitter: float = 0.0
var delay: float = 0.0
var samples: int = 0
var starved: int = 0


func observe(sent_time: float, local_time: float, smoothing: float) -> void:
	var sample := local_time - sent_time
	if samples == 0:
		offset = sample
	else:
		jitter = lerpf(jitter, absf(sample - offset), smoothing)
		offset = lerpf(offset, sample, smoothing)
	samples += 1


func remote_time(local_time: float) -> float:
	return local_time - offset


func sample_time(local_time: float, latest_sent_time: float, send_interval: float, min_delay: float, max_delay: float, jitter_scale: float, shrink_rate: float, delta: float) -> float:
	var wanted := clampf(send_interval * 1.5 + jitter * jitter_scale, min_delay, max_delay)
	delay = wanted if wanted > delay else move_toward(delay, wanted, shrink_rate * delta)
	var time := remote_time(local_time) - delay
	if time > latest_sent_time:
		starved += 1
		delay = minf(delay + (time - latest_sent_time), max_delay)
		time = latest_sent_time
	return time
