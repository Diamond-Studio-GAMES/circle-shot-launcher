class_name Downloader
extends Window


enum Status {
	IDLE = 0,
	DOWNLOADING_ENGINE = 1,
	DOWNLOADING_PACK = 2,
	UNZIPPING_PACK = 3,
	UNZIPPING_ENGINE = 4,
}

var status := Status.IDLE
var _download_version_code: String
var _download_engine_version: String

@onready var _launcher: Launcher = get_parent()
@onready var _remote_manager: RemoteManager = _launcher.get_node(^"RemoteManager")
@onready var _pack_http: HTTPRequest = $PackDownloadHTTPRequest
@onready var _engine_http: HTTPRequest = $EngineDownloadHTTPRequest
@onready var _status_label: Label = $VBoxContainer/DownloadingStatus
@onready var _progress_bar: ProgressBar = $VBoxContainer/DownloadingProgress


func _process(_delta: float) -> void:
	match status:
		Status.IDLE:
			_progress_bar.value = 0.0
			_status_label.text = ""
		Status.DOWNLOADING_ENGINE:
			if _engine_http.get_body_size() > 0:
				_progress_bar.value = \
						float(_engine_http.get_downloaded_bytes()) / _engine_http.get_body_size()
				_status_label.text = "Скачиваю движок... (%s / %s)" % [
					String.humanize_size(_engine_http.get_downloaded_bytes()),
					String.humanize_size(_engine_http.get_body_size())
				]
			else:
				_progress_bar.value = 0.0
				_status_label.text = "Скачиваю движок..."
		Status.DOWNLOADING_PACK:
			if _pack_http.get_body_size() > 0:
				_progress_bar.value = \
						float(_pack_http.get_downloaded_bytes()) / _pack_http.get_body_size()
				_status_label.text = "Скачиваю ресурсы... (%s / %s)" % [
					String.humanize_size(_pack_http.get_downloaded_bytes()),
					String.humanize_size(_pack_http.get_body_size())
				]
			else:
				_progress_bar.value = 0.0
				_status_label.text = "Скачиваю ресурсы..."
		Status.UNZIPPING_PACK:
			_progress_bar.value = 1.0
			_status_label.text = "Распаковка ресурсов..."
		Status.UNZIPPING_ENGINE:
			_progress_bar.value = 1.0
			_status_label.text = "Распаковка движка..."


func download_version(version_code: String, engine_version: String) -> void:
	if version_code in _launcher.versions_file.get_sections():
		push_error("This version is already installed!")
		return
	_download_engine_version = engine_version
	_download_version_code = version_code
	title = "Скачивание %s..." % _remote_manager.remote_versions.get_value(version_code, "name")
	popup_centered()
	var should_install_engine := true
	for installed_version_code: String in _launcher.versions_file.get_sections():
		if _launcher.versions_file.get_value(installed_version_code, "engine_version") \
				== engine_version:
			should_install_engine = false
			break
	if should_install_engine:
		_download_engine()
		return
	_download_pack()


func _download_engine() -> void:
	_engine_http.download_file = _launcher.data_path.path_join("tmp.engine.zip")
	var engine_name: String = "engine.%s.%s.%s.zip" % [
		_download_engine_version,
		OS.get_name(),
		Engine.get_architecture_name()
	]
	engine_name = engine_name.to_lower()
	var url: String = _launcher.get_server_url().path_join("engines").path_join(engine_name)
	print("Downloading engine from %s..." % url)
	status = Status.DOWNLOADING_ENGINE
	var err: Error = _engine_http.request(url)
	if err != OK:
		push_error("Can't download engine. Error: %s." % error_string(err))
		_show_message("Ошибка скачивания движка.")
		_cleanup()


func _download_pack() -> void:
	_pack_http.download_file = _launcher.data_path.path_join("tmp.pack.zip")
	var pack_name: String = "pack.%s.%s.zip" % [
		_download_version_code,
		OS.get_name()
	]
	pack_name = pack_name.to_lower()
	var url: String = _launcher.get_server_url().path_join("packs").path_join(pack_name)
	print("Downloading pack from %s..." % url)
	status = Status.DOWNLOADING_PACK
	var err: Error = _pack_http.request(url)
	if err != OK:
		push_error("Can't download pack. Error: %s." % error_string(err))
		_cleanup()
		_show_message("Ошибка скачивания ресурсов.")


func _unzip_and_install() -> void:
	status = Status.UNZIPPING_PACK
	await get_tree().process_frame
	await get_tree().process_frame
	
	var zip := ZIPReader.new()
	
	var err: Error = zip.open(_launcher.data_path.path_join("tmp.pack.zip"))
	if err != OK:
		push_error("Error unzipping tmp.pack.zip: %s." % error_string(err))
		_cleanup()
		_show_message("Ошибка распаковки ресурсов.")
		return
	if not zip.file_exists("pack"):
		push_error("tmp.pack.zip is incorrect.")
		_cleanup()
		_show_message("Неправильный формат архива с ресурсами.")
		return
	var pack_file := FileAccess.open(
			_launcher.get_version_pack_path(_download_version_code), FileAccess.WRITE
	)
	if not pack_file:
		push_error("Error creating pack file at path %s. Error: %s" % [
			_launcher.get_version_pack_path(_download_version_code),
			error_string(FileAccess.get_open_error())
		])
		_cleanup()
		_show_message("Ошибка распаковки файла ресурсов!")
		return
	pack_file.store_buffer(zip.read_file("pack"))
	pack_file.close()
	zip.close()
	
	if FileAccess.file_exists(_launcher.data_path.path_join("tmp.engine.zip")):
		status = Status.UNZIPPING_ENGINE
		await get_tree().process_frame
		
		err = zip.open(_launcher.data_path.path_join("tmp.engine.zip"))
		if err != OK:
			push_error("Error unzipping tmp.engine.zip: %s." % error_string(err))
			_cleanup()
			_show_message("Ошибка распаковки движка")
			return
		if not zip.file_exists("engine"):
			push_error("tmp.engine.zip is incorrect.")
			_cleanup()
			_show_message("Неправильный формат архива с движком.")
			return
		var engine_file := FileAccess.open(
				_launcher.get_version_engine_path("", _download_engine_version), FileAccess.WRITE
		)
		if not engine_file:
			push_error("Error creating engine file at path %s. Error: %s" % [
				_launcher.get_version_engine_path("", _download_engine_version),
				error_string(FileAccess.get_open_error())
			])
			_cleanup()
			_show_message("Ошибка распаковки движка.")
			return
		engine_file.store_buffer(zip.read_file("engine"))
		if OS.has_feature("linux"):
			# Выдаём разрешения на запуск
			OS.execute("/bin/chmod", PackedStringArray(["+x", engine_file.get_path_absolute()]))
		engine_file.close()
		zip.close()
	
	_launcher.versions_file.set_value(
			_download_version_code, "name",
			_remote_manager.remote_versions.get_value(_download_version_code, "name")
	)
	_launcher.versions_file.set_value(
			_download_version_code, "engine_version", _download_engine_version
	)
	_launcher.versions_file.set_value(
			_download_version_code, "beta",
			_remote_manager.remote_versions.get_value(_download_version_code, "beta")
	)
	
	print("Unzip and install ended.")
	_cleanup()
	_show_message(
			"Версия %s успешно скачана и установлена."
			% _launcher.versions_file.get_value(_download_version_code, "name"),
			"Скачивание"
	)
	_launcher.list_local_versions()


func _cleanup() -> void:
	status = Status.IDLE
	if FileAccess.file_exists(_launcher.data_path.path_join("tmp.engine.zip")):
		DirAccess.remove_absolute(_launcher.data_path.path_join("tmp.engine.zip"))
	if FileAccess.file_exists(_launcher.data_path.path_join("tmp.pack.zip")):
		DirAccess.remove_absolute(_launcher.data_path.path_join("tmp.pack.zip"))
	hide()


func _show_message(message_text: String, message_title := "Ошибка!") -> void:
	var dialog := AcceptDialog.new()
	dialog.unresizable = true
	dialog.dialog_text = message_text
	dialog.title = message_title
	_launcher.add_child(dialog)
	dialog.popup_centered()
	dialog.visibility_changed.connect(dialog.queue_free)


func _on_engine_download_http_request_request_completed(result: HTTPRequest.Result, 
		response_code: HTTPClient.ResponseCode, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Download engine: result (%d) is not Success!" % result)
		_cleanup()
		_show_message("Ошибка загрузки движка.")
		return
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Download engine: response code (%d) is not 200!" % response_code)
		_cleanup()
		_show_message("Ошибка загрузки движка.")
		return
	print("Engine downloaded.")
	_download_pack()


func _on_pack_download_http_request_request_completed(result: HTTPRequest.Result, 
		response_code: HTTPClient.ResponseCode, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Download pack: result (%d) is not Success!" % result)
		_cleanup()
		_show_message("Ошибка загрузки ресурсов.")
		return
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Download pack: response code (%d) is not 200!" % response_code)
		_cleanup()
		_show_message("Ошибка загрузки ресурсов.")
		return
	print("Pack downloaded. Unzipping.")
	_unzip_and_install()


func _on_close_requested() -> void:
	match status:
		Status.DOWNLOADING_ENGINE:
			_engine_http.cancel_request()
		Status.DOWNLOADING_PACK:
			_pack_http.cancel_request()
		_:
			return
	_cleanup()
	_show_message("Загрузка прервана.")
