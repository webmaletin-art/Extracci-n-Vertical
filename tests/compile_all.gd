extends Node
## Carga todos los scripts del proyecto para detectar errores de compilación (lo usa tools/run_tests.sh).
func _ready() -> void:
	var bad := 0
	var stack := ["res://systems", "res://scenes", "res://tests"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for d in DirAccess.get_directories_at(dir):
			stack.append(dir.path_join(d))
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var s = load(dir.path_join(f))
				if s == null or not (s as GDScript).can_instantiate():
					print("FALLA COMPILAR: ", dir.path_join(f))
					bad += 1
	print("compilación: ", "OK" if bad == 0 else "%d con errores" % bad)
	get_tree().quit(1 if bad > 0 else 0)
