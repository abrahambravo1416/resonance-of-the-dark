extends SceneTree

const ICON_OUTPUTS := [
	{
		"source": "res://icon.svg",
		"destination": "res://assets/ui/launcher_main_192.png",
		"size": 192,
		"resize": true,
	},
	{
		"source": "res://assets/ui/launcher_adaptive_foreground.svg",
		"destination": "res://assets/ui/launcher_adaptive_foreground_432.png",
		"size": 432,
		"resize": false,
	},
	{
		"source": "res://assets/ui/launcher_adaptive_background.svg",
		"destination": "res://assets/ui/launcher_adaptive_background_432.png",
		"size": 432,
		"resize": false,
	},
	{
		"source": "res://assets/ui/launcher_adaptive_monochrome.svg",
		"destination": "res://assets/ui/launcher_adaptive_monochrome_432.png",
		"size": 432,
		"resize": false,
	},
]


func _initialize() -> void:
	for icon_data: Dictionary in ICON_OUTPUTS:
		var image := Image.new()
		var error: Error = image.load_svg_from_string(
			FileAccess.get_file_as_string(icon_data.source)
		)
		if error != OK:
			push_error("No se pudo renderizar %s: %s" % [icon_data.source, error_string(error)])
			quit(1)
			return

		if icon_data.resize:
			image.resize(icon_data.size, icon_data.size, Image.INTERPOLATE_LANCZOS)
		var save_error: Error = image.save_png(icon_data.destination)
		if save_error != OK:
			push_error("No se pudo guardar %s: %s" % [icon_data.destination, error_string(save_error)])
			quit(1)
			return
		print("Icono generado: %s" % icon_data.destination)

	quit(0)
