extends MeshInstance3D
class_name LassoMesh

@export var radius: float = 0.02
@export var radial_segments: int = 8
@export var rope_color: Color = Color(0.76, 0.6, 0.42) # A brownish rope color

var surface_tool := SurfaceTool.new()

## Generates a procedural tube/rope mesh along a path of Vector3 points
func generate_lasso_mesh(points: PackedVector3Array) -> void:
	if points.size() < 2:
		mesh = null
		return

	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate total length to assign proper V coordinates for UV mapping
	var total_length := 0.0
	var lengths := PackedFloat32Array()
	lengths.append(0.0)
	for i in range(1, points.size()):
		total_length += points[i].distance_to(points[i-1])
		lengths.append(total_length)

	var up_vector := Vector3.UP

	# Create rings of vertices along the points
	for i in range(points.size()):
		var p = points[i]
		var dir := Vector3.FORWARD

		# Determine the forward direction for this segment
		if i < points.size() - 1:
			dir = (points[i+1] - p).normalized()
		else:
			dir = (p - points[i-1]).normalized()

		# Prevent cross product zero-vector issues if looking straight up/down
		if abs(dir.dot(Vector3.UP)) > 0.99:
			up_vector = Vector3.RIGHT
		else:
			up_vector = Vector3.UP

		var right = dir.cross(up_vector).normalized()
		var local_up = right.cross(dir).normalized()

		var v_uv = lengths[i]

		# Build the circular profile around the point
		for j in range(radial_segments + 1):
			var angle = float(j) / float(radial_segments) * TAU
			var cos_a = cos(angle)
			var sin_a = sin(angle)

			var normal = (right * cos_a + local_up * sin_a).normalized()
			var vertex = p + normal * radius

			var u_uv = float(j) / float(radial_segments)

			surface_tool.set_color(rope_color)
			surface_tool.set_normal(normal)
			surface_tool.set_uv(Vector2(u_uv, v_uv))
			surface_tool.add_vertex(vertex)

	# Generate triangles connecting the rings
	for i in range(points.size() - 1):
		for j in range(radial_segments):
			var current_ring = i * (radial_segments + 1)
			var next_ring = (i + 1) * (radial_segments + 1)

			var v0 = current_ring + j
			var v1 = current_ring + j + 1
			var v2 = next_ring + j
			var v3 = next_ring + j + 1

			# Triangle 1
			surface_tool.add_index(v0)
			surface_tool.add_index(v2)
			surface_tool.add_index(v1)

			# Triangle 2
			surface_tool.add_index(v1)
			surface_tool.add_index(v2)
			surface_tool.add_index(v3)

	# Commit the generated geometry to an ArrayMesh and assign it
	surface_tool.generate_tangents()
	mesh = surface_tool.commit()
