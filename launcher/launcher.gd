class_name Launcher
extends Control


var settings_file := ConfigFile.new()
var versions_file := ConfigFile.new()
var data_path: String
var executable_suffix: String
var _version_scene: PackedScene = preload("uid://cw77pm0u17yb6")
@onready var _status: Label = $Status
@onready var _reset_status_timer: Timer = $ResetStatusTimer


func _ready() -> void:
	if FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("_sc_")) \
			or FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("._sc_")):
		#data_path = OS.get_executable_path().path_join("data")
		data_path = "/tmp/data"
	else:
		data_path = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(data_path)
	print("Data path set to %s." % data_path)
	
	settings_file.load(data_path.path_join("settings.cfg"))
	versions_file.load(data_path.path_join("versions.cfg"))
	
	if OS.get_name() == "Windows":
		executable_suffix = ".exe"
	
	list_local_versions()


func save_files() -> void:
	settings_file.save(data_path.path_join("settings.cfg"))
	versions_file.save(data_path.path_join("versions.cfg"))


func list_local_versions() -> void:
	for child: Node in %Versions.get_children():
		if child.name == &"NoVersions":
			continue
		%Versions.remove_child(child)
		child.queue_free()
	
	var version_nodes: Array[Node]
	for version: String in versions_file.get_sections():
		if not _is_version_files_valid(version):
			push_error("Found incorrect version config: %s." % _get_version_name(version))
			versions_file.erase_section(version)
			continue
		
		var version_node: PanelContainer = _version_scene.instantiate()
		version_node.name = StringName(version)
		var version_name: String = "Версия %s" % _get_version_name(version)
		if versions_file.get_value(version, "beta", false):
			version_name += " (БЕТА)"
		(version_node.get_node(^"%VersionName") as Label).text = version_name
		(version_node.get_node(^"%Run") as Button).pressed.connect(run_version.bind(version))
		(version_node.get_node(^"%Export") as Button).pressed.connect(export_version.bind(version))
		(version_node.get_node(^"%Remove") as Button).pressed.connect(remove_version.bind(version))
		version_nodes.append(version_node)
	
	version_nodes.sort_custom(func(first: Node, second: Node) -> bool:
		return int(first.name) < int(second.name))
	
	if version_nodes.is_empty():
		(%Versions/NoVersions as CanvasItem).show()
	else:
		(%Versions/NoVersions as CanvasItem).hide()
		for node: Node in version_nodes:
			%Versions.add_child(node)
			%Versions.move_child(node, 0)
		var newest_label: Label = %Versions.get_child(0).get_node(^"%VersionName")
		newest_label.text = "Новейшая " + newest_label.text
	save_files()


func run_version(version: String) -> void:
	_status.text = "Запускаю версию %s..." % _get_version_name(version)
	print("Starting version %s..." % _get_version_name(version))
	
	if not _is_version_files_valid(version):
		push_error("Run: can't find files of version %s." % _get_version_name(version))
		_status.text = "Запуск: файлы версии не найдены."
		_reset_status_timer.start()
		return
	
	var executable_path: String = _get_version_executable_path(version)
	var pack_path: String = _get_version_pack_path(version)
	var pid: int = OS.create_process(executable_path, PackedStringArray(["--main-pack", pack_path]))
	if pid == -1:
		push_error("Can't start game with executable path %s and pack path %s!" % [
			executable_path,
			pack_path
		])
		_status.text = "Невозможно запустить игру!"
		_reset_status_timer.start()
	else:
		print("Started. PID: %d." % pid)
		get_tree().quit.call_deferred()


func export_version(version: String) -> void:
	if not _is_version_files_valid(version):
		push_error("Export: can't find files of version %s." % _get_version_name(version))
		_status.text = "Экспорт: файлы версии не найдены."
		_reset_status_timer.start()
		return
	
	var efd: FileDialog = $ExportFileDialog
	efd.title = "Экспорт версии %s" % _get_version_name(version)
	efd.file_selected.connect(_on_export_file_dialog_file_selected.bind(version))
	efd.popup_centered()
	efd.visibility_changed.connect(
			efd.file_selected.disconnect.bind(_on_export_file_dialog_file_selected),
			CONNECT_DEFERRED
	)


func remove_version(version: String) -> void:
	pass


func _get_version_name(version: String) -> String:
	return versions_file.get_value(version, "name")


func _is_version_files_valid(version: String) -> bool:
	return FileAccess.file_exists(_get_version_executable_path(version)) \
			and FileAccess.file_exists(_get_version_pack_path(version))


func _get_version_executable_path(version: String) -> String:
	return data_path.path_join(
			"engine." + str(versions_file.get_value(version, "engine_version", "4.0"))
			+ executable_suffix
	)


func _get_version_pack_path(version: String) -> String:
	return data_path.path_join("data." + version + ".pck")


func _on_export_file_dialog_file_selected(path: String, version: String) -> void:
	if not _is_version_files_valid(version):
		push_error("Export: can't find files of version %s." % _get_version_name(version))
		_status.text = "Экспорт: файлы версии не найдены."
		_reset_status_timer.start()
		return
	
	print("Exporting to %s." % path)
	_status.text = "Выполняется экспорт..."
	await get_tree().process_frame
	await get_tree().process_frame
	
	var zip := ZIPPacker.new()
	var err: Error = zip.open(path)
	if err != OK:
		_status.text = "Ошибка создания ZIP-файла!"
		_reset_status_timer.start()
		return
	
	var config := ConfigFile.new()
	config.set_value("config", "name", _get_version_name(version))
	config.set_value("config", "code", version)
	config.set_value("config", "engine_version", \
			versions_file.get_value(version, "engine_version", "4.0"))
	config.set_value("config", "arch", Engine.get_architecture_name())
	config.set_value("config", "platform", OS.get_name())
	
	zip.start_file("version.cfg")
	zip.write_file(config.encode_to_text().to_utf8_buffer())
	zip.close_file()
	
	zip.start_file("engine")
	zip.write_file(FileAccess.get_file_as_bytes(_get_version_executable_path(version)))
	zip.close_file()
	
	zip.start_file("data")
	zip.write_file(FileAccess.get_file_as_bytes(_get_version_pack_path(version)))
	zip.close_file()
	
	zip.close()
	print("Export ended.")
	_status.text = "Экспорт завершён."
	_reset_status_timer.start()
