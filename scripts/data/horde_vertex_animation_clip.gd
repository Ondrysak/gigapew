class_name HordeVertexAnimationClip
extends Resource

## One baked clip inside a HordeVertexAnimation: a run of consecutive frames.

@export var name: StringName
## First frame (texture row block) of the clip.
@export var start_frame := 0
@export var frame_count := 1
## Frames per second the clip was sampled at; playing at this rate is real time.
@export var fps := 20.0
## Looping clips wrap from the last frame to the first; others hold the last frame.
@export var loop := true

## Clip length in seconds at natural speed.
func duration() -> float:
	return float(frame_count if loop else maxi(1, frame_count - 1)) / maxf(0.001, fps)
