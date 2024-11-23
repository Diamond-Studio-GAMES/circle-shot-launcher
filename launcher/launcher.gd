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
		# ANGLE библиотеки момент
		var gles_path: String = OS.get_executable_path().get_base_dir().path_join("libGLESv2.dll")
		var egl_path: String = OS.get_executable_path().get_base_dir().path_join("libEGL.dll")
		var gles_dest_path: String = data_path.path_join("libGLESv2.dll")
		var egl_dest_path: String = data_path.path_join("libEGL.dll")
		if FileAccess.file_exists(gles_path) and not FileAccess.file_exists(gles_dest_path):
			DirAccess.copy_absolute(gles_path, gles_dest_path)
		if FileAccess.file_exists(egl_path) and not FileAccess.file_exists(egl_dest_path):
			DirAccess.copy_absolute(egl_path, egl_dest_path)
	
	($ExportFileDialog as FileDialog).current_dir = data_path
	($ImportFileDialog as FileDialog).current_dir = data_path
	
	list_local_versions()
	
	($Settings as InstancePlaceholder).create_instance(true)
	($RemoteManager as InstancePlaceholder).create_instance(true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PREDELETE, \
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_files()


func save_files() -> void:
	settings_file.save(data_path.path_join("settings.cfg"))
	versions_file.save(data_path.path_join("versions.cfg"))


func list_local_versions() -> void:
	_validate_version_configs()
	
	for child: Node in %Versions.get_children():
		if child.name == &"NoVersions":
			continue
		%Versions.remove_child(child)
		child.queue_free()
	
	var version_nodes: Array[Node]
	for version_code: String in versions_file.get_sections():
		var version_node: PanelContainer = _version_scene.instantiate()
		version_node.name = StringName(version_code)
		var version_name: String = "Версия %s" % _get_version_name(version_code)
		if versions_file.get_value(version_code, "beta"):
			version_name += " (БЕТА)"
		(version_node.get_node(^"%VersionName") as Label).text = version_name
		(version_node.get_node(^"%Run") as Button).pressed.connect(
				run_version.bind(version_code)
		)
		(version_node.get_node(^"%Export") as Button).pressed.connect(
				export_version.bind(version_code)
		)
		(version_node.get_node(^"%Remove") as Button).pressed.connect(
				remove_version.bind(version_code)
		)
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


func run_version(version_code: String) -> void:
	_status.text = "Запускаю версию %s..." % _get_version_name(version_code)
	print("Starting version %s..." % _get_version_name(version_code))
	
	if not _is_version_files_valid(version_code):
		_validate_version_configs()
		push_error("Run: can't find files of version %s." % _get_version_name(version_code))
		_status.text = "Запуск: файлы версии не найдены. Удаляю эту версию."
		_reset_status_timer.start()
		_remove_version(version_code)
		return
	
	var executable_path: String = _get_version_engine_path(version_code)
	var pack_path: String = _get_version_pack_path(version_code)
	var arguments: Array[String] = ["--main-pack", pack_path]
	var custom_arguments: PackedStringArray = \
			str(settings_file.get_value("settings", "arguments")).split(' ')
	for i: String in custom_arguments:
		arguments.append(i)
	var pid: int = OS.create_process(executable_path, arguments)
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


func export_version(version_code: String) -> void:
	if not _is_version_files_valid(version_code):
		push_error("Export: can't find files of version %s." % _get_version_name(version_code))
		_status.text = "Экспорт: файлы версии не найдены. Удаляю эту версию."
		_reset_status_timer.start()
		_remove_version(version_code)
		return
	
	var efd: FileDialog = $ExportFileDialog
	efd.title = "Экспорт версии %s" % _get_version_name(version_code)
	efd.current_file = "game_v%s.zip" % _get_version_name(version_code)
	efd.file_selected.connect(_export_version.bind(version_code))
	efd.popup_centered()
	($MouseBlock as CanvasItem).show()


func import_version() -> void:
	($ImportFileDialog as FileDialog).popup_centered()
	($MouseBlock as CanvasItem).show()


func remove_version(version_code: String) -> void:
	var dd: ConfirmationDialog = $DeleteDialog
	dd.dialog_text = "Удалить версию %s?" % _get_version_name(version_code)
	dd.confirmed.connect(_remove_version.bind(version_code, true))
	dd.popup_centered()
	dd.visibility_changed.connect(
			dd.confirmed.disconnect.bind(_remove_version),
			CONNECT_DEFERRED | CONNECT_ONE_SHOT
	)


func get_server_url() -> String:
	return settings_file.get_value("settings", "server")


func _export_version(path: String, version_code: String) -> void:
	if not _is_version_files_valid(version_code):
		push_error("Export: can't find files of version %s." % _get_version_name(version_code))
		_status.text = "Экспорт: файлы версии не найдены. Удаляю эту версию."
		_reset_status_timer.start()
		_remove_version(version_code)
		return
	
	print("Exporting to %s." % path)
	_status.text = "Выполняется экспорт..."
	($MouseBlock as CanvasItem).show()
	await get_tree().process_frame
	await get_tree().process_frame
	
	var zip := ZIPPacker.new()
	var err: Error = zip.open(path)
	if err != OK:
		_status.text = "Ошибка создания ZIP-файла!"
		push_error("Creating ZIP failed with error %s." % error_string(err))
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	var config := ConfigFile.new()
	config.set_value("config", "name", _get_version_name(version_code))
	config.set_value("config", "code", version_code)
	config.set_value("config", "engine_version", \
			versions_file.get_value(version_code, "engine_version"))
	config.set_value("config", "arch", Engine.get_architecture_name())
	config.set_value("config", "platform", OS.get_name())
	config.set_value("config", "beta", versions_file.get_value(version_code, "beta"))
	
	zip.start_file("version.cfg")
	zip.write_file(config.encode_to_text().to_utf8_buffer())
	zip.close_file()
	
	zip.start_file("engine")
	zip.write_file(FileAccess.get_file_as_bytes(_get_version_engine_path(version_code)))
	zip.close_file()
	
	zip.start_file("pack")
	zip.write_file(FileAccess.get_file_as_bytes(_get_version_pack_path(version_code)))
	zip.close_file()
	
	zip.close()
	print("Export ended.")
	_status.text = "Экспорт завершён."
	_reset_status_timer.start()
	await get_tree().process_frame # Чтобы точно никакие события мыши не прошли
	($MouseBlock as CanvasItem).hide()


func _import_version(path: String) -> void:
	print("Importing from %s." % path)
	_status.text = "Выполняется импорт..."
	($MouseBlock as CanvasItem).show()
	await get_tree().process_frame
	await get_tree().process_frame
	
	var zip := ZIPReader.new()
	var err: Error = zip.open(path)
	if err != OK:
		_status.text = "Ошибка открытия ZIP-файла!"
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	if not (
			zip.file_exists("engine")
			and zip.file_exists("pack")
			and zip.file_exists("version.cfg")
	):
		_status.text = "В этом ZIP-файле нет нужных файлов."
		push_error("ZIP file is missing some files (engine, pack, versions.cfg)")
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	var config := ConfigFile.new()
	err = config.parse(zip.read_file("version.cfg").get_string_from_utf8())
	if err != OK:
		_status.text = "Не могу открыть файл конфигурации в этом архиве!"
		push_error("versions.cfg can't be parsed.")
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	if not (
			config.has_section_key("config", "code")
			and str(config.get_value("config", "code")).is_valid_int()
			and config.has_section_key("config", "name")
			and typeof(config.get_value("config", "name")) == TYPE_STRING
			and config.has_section_key("config", "engine_version")
			and typeof(config.get_value("config", "engine_version")) == TYPE_STRING
			and config.has_section_key("config", "arch")
			and typeof(config.get_value("config", "arch")) == TYPE_STRING
			and config.has_section_key("config", "platform")
			and typeof(config.get_value("config", "platform")) == TYPE_STRING
			and config.has_section_key("config", "beta")
			and typeof(config.get_value("config", "beta")) == TYPE_BOOL
	):
		_status.text = "Файл конфигурации в этом архиве содержит не всю информацию!"
		push_error("versions.cfg don't have all needed information.")
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	var new_version_code: String = config.get_value("config", "code")
	var engine_version: String = config.get_value("config", "engine_version")
	
	if new_version_code in versions_file.get_sections():
		_status.text = "Эта версия (%s) уже установлена!" % _get_version_name(new_version_code)
		push_error("This version (%s) is already installed." % _get_version_name(new_version_code))
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	if config.get_value("config", "platform") != OS.get_name():
		_status.text = "Эта версия несовместима с вашей операционной системой!"
		push_error("Incompatible platforms.")
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	var engine_already_installed := false
	for version_code: String in versions_file.get_sections():
		if versions_file.get_value(version_code, "engine_version", "-1.0") == engine_version:
			engine_already_installed = true
			break
	
	if not engine_already_installed \
			and config.get_value("config", "arch") != Engine.get_architecture_name():
		_status.text = "Эта версия несовместима с вашей архитектурой процессора!"
		push_error("Engine this needed version not found. Engine in archive uses different arch.")
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	
	# Всё наконец-то ОК, распаковываем!
	var pack_file := FileAccess.open(_get_version_pack_path(new_version_code), FileAccess.WRITE)
	if not pack_file:
		_status.text = "Ошибка распаковки файла с ресурсами!"
		push_error("Error creating pack file at path %s. Error: %s" % [
			_get_version_pack_path(new_version_code),
			error_string(FileAccess.get_open_error())
		])
		_reset_status_timer.start()
		($MouseBlock as CanvasItem).hide()
		return
	pack_file.store_buffer(zip.read_file("pack"))
	pack_file.close()
	
	if not engine_already_installed:
		var engine_file := FileAccess.open(
			_get_version_engine_path("", engine_version), FileAccess.WRITE
		)
		if not engine_file:
			_status.text = "Ошибка распаковки файла движка!"
			push_error("Error creating engine file at path %s. Error: %s" % [
				_get_version_engine_path("", engine_version),
				error_string(FileAccess.get_open_error())
			])
			_reset_status_timer.start()
			($MouseBlock as CanvasItem).hide()
			return
		engine_file.store_buffer(zip.read_file("engine"))
		engine_file.close()
		
		if OS.has_feature("linux"):
			# Выдаём разрешения на запуск
			OS.execute("/bin/chmod", PackedStringArray(["+x", engine_file.get_path_absolute()]))
	
	versions_file.set_value(new_version_code, "name", config.get_value("config", "name"))
	versions_file.set_value(new_version_code, "beta", config.get_value("config", "beta"))
	versions_file.set_value(new_version_code, "engine_version", engine_version)
	save_files()
	list_local_versions()
	_status.text = "Импорт версии %s завершён." % _get_version_name(new_version_code)
	_reset_status_timer.start()
	($MouseBlock as CanvasItem).hide()
	print("Import of version %s ended." % _get_version_name(new_version_code))
	($RemoteManager as RemoteManager).list_remote_versions()


func _remove_version(version_code: String, show_message := false) -> void:
	DirAccess.remove_absolute(_get_version_pack_path(version_code))
	
	var delete_engine := true
	for section: String in versions_file.get_sections():
		if version_code == section:
			continue
		if versions_file.get_value(version_code, "engine_version", "-1.0") == \
				versions_file.get_value(section, "engine_version", "-2.0"):
			delete_engine = false
			break
	
	if delete_engine:
		DirAccess.remove_absolute(_get_version_engine_path(version_code))
	
	var version_name: String = _get_version_name(version_code)
	versions_file.erase_section(version_code)
	print("Removed version %s." % version_code)
	list_local_versions()
	if show_message:
		_status.text = "Версия %s удалена." % version_name
		_reset_status_timer.start()
	($RemoteManager as RemoteManager).list_remote_versions()


func _validate_version_configs() -> void:
	for version_code: String in versions_file.get_sections():
		if not (
				version_code.is_valid_int()
				and versions_file.has_section_key(version_code, "name")
				and versions_file.has_section_key(version_code, "engine_version")
				and versions_file.has_section_key(version_code, "beta")
				and _is_version_files_valid(version_code)
		):
			push_error("Found incorrect version config: %s." % _get_version_name(version_code))
			_remove_version(version_code)
	
	save_files()


func _get_version_name(version_code: String) -> String:
	return versions_file.get_value(version_code, "name", version_code)


func _get_version_engine_path(version_code: String, engine_version := "") -> String:
	if engine_version.is_empty():
		return data_path.path_join(
				"engine." + str(versions_file.get_value(version_code, "engine_version"))
				+ executable_suffix
		)
	return data_path.path_join("engine." + engine_version + executable_suffix)


func _get_version_pack_path(version_code: String) -> String:
	return data_path.path_join("pack." + version_code + ".pck")


func _is_version_files_valid(version_code: String) -> bool:
	return FileAccess.file_exists(_get_version_engine_path(version_code)) \
			and FileAccess.file_exists(_get_version_pack_path(version_code))


func _on_export_file_dialog_canceled() -> void:
	($ExportFileDialog as FileDialog).file_selected.disconnect(_export_version)
	($MouseBlock as CanvasItem).hide()


func _on_import_file_dialog_canceled() -> void:
	($MouseBlock as CanvasItem).hide()


func _on_settings_pressed() -> void:
	($Settings as Window).popup_centered()


func _on_download_pressed() -> void:
	($RemoteManager as Window).popup_centered()
