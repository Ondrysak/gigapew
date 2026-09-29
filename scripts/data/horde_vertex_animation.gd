class_name HordeVertexAnimation
extends Resource

## Vertex Animation Texture set baked by tools/vat/bake_vat.py. Each texel column
## holds one mesh vertex (the mesh's UV2.x = (column + 0.5) / vertex_count), each
## frame occupies `rows_per_frame` rows; clips are stacked frame blocks. Textures
## hold Godot-space model positions/normals as 32-bit floats (sampled with
## texelFetch, so they must be imported lossless, without mipmaps).

@export var positions: Texture2D
@export var normals: Texture2D
@export var vertex_count := 1
@export var clips: Array[HordeVertexAnimationClip] = []

## Index of the clip called `clip_name`, or -1 (also for an empty name).
func find_clip(clip_name: StringName) -> int:
	if clip_name == &"":
		return -1
	for index in clips.size():
		if clips[index].name == clip_name:
			return index
	return -1

## Texture rows per frame (columns wrap when vertex_count exceeds the width).
func rows_per_frame() -> int:
	var width := positions.get_width() if positions != null else vertex_count
	return ceili(float(vertex_count) / float(maxi(1, width)))
