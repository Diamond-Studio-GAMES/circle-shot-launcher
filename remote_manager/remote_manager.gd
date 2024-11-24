class_name RemoteManager
extends Window


var remote_versions := ConfigFile.new()
var remote_engine_versions := ConfigFile.new()
var versions_downloaded := false
var update_showed := false

var _remote_version_scene: PackedScene = preload("uid://b2y07vkguxpwu")

@onready var _launcher: Launcher = get_parent()
@onready var _versions_http: HTTPRequest = $VersionsHTTPRequest
@onready var _engine_versions_http: HTTPRequest = $EngineVersionsHTTPRequest
@onready var _status: Label = %Versions/Status
@onready var _update_button: Button = %Update


func _ready() -> void:
	download_remote_configs()


func download_remote_configs() -> void:
	_clear_versions()
	versions_downloaded = false
	update_showed = false
	_status.show()
	_status.text = "Скачивание списка версий..."
	_update_button.disabled = true
	var err: Error = _versions_http.request(
			_launcher.get_server_url().path_join("remote_versions.cfg")
	)
	if err != OK:
		push_error("Get versions failed. Error: %s." % error_string(err))
		_status.text = "Ошибка скачивания списка версий: %s!" % error_string(err)
		_update_button.disabled = false
		return


func list_remote_versions() -> void:
	if not versions_downloaded:
		return
	_clear_versions()
	
	var my_edition: String = OS.get_name() + "." + Engine.get_architecture_name()
	var supported_engines: Array[String]
	for engine_version: String in remote_engine_versions.get_sections():
		var editions: Array = remote_engine_versions.get_value(engine_version, "editions")
		if my_edition in editions:
			supported_engines.append(engine_version)
	prints("Supported remote engines:", supported_engines)
	
	var installed_engines: Array[String]
	for version_code: String in _launcher.versions_file.get_sections():
		installed_engines.append(_launcher.versions_file.get_value(version_code, "engine_version"))
	prints("Installed engines:", supported_engines)
	
	var version_nodes: Array[Node]
	var highest_version: int = -1
	for version_code: String in remote_versions.get_sections():
		print("Checking version %s (%s)." % [
			remote_versions.get_value(version_code, "name"),
			version_code
		])
		var engine_version: String = remote_versions.get_value(version_code, "engine_version")
		if not (engine_version in installed_engines or engine_version in supported_engines):
			print("Incompatible engine: %s." % engine_version)
			continue
		if not OS.get_name() in remote_versions.get_value(version_code, "platforms"):
			print("Incompatible platform: %s. Supported: %s." % [
				OS.get_name(),
				str(remote_versions.get_value(version_code, "platforms"))
			])
			continue
		if remote_versions.get_value(version_code, "beta") \
				and not _launcher.settings_file.get_value("settings", "betas"):
			continue
		
		var remote_version_node: PanelContainer = _remote_version_scene.instantiate()
		remote_version_node.name = StringName(version_code)
		var version_name: String = "Версия %s" % remote_versions.get_value(version_code, "name")
		if remote_versions.get_value(version_code, "beta"):
			version_name += " (БЕТА)"
		(remote_version_node.get_node(^"%VersionName") as Label).text = version_name
		if not version_code in _launcher.versions_file.get_sections():
			(remote_version_node.get_node(^"%Download") as BaseButton).pressed.connect(
					_download_version_confirm.bind(version_code, engine_version)
			)
		else:
			(remote_version_node.get_node(^"%Download") as BaseButton).disabled = true
			(remote_version_node.get_node(^"%Download") as Button).text = "Скачано"
		version_nodes.append(remote_version_node)
		
		if int(version_code) > highest_version:
			if not remote_versions.get_value(version_code, "beta"):
				highest_version = int(version_code)
			elif _launcher.settings_file.get_value("settings", "beta_updates"):
				highest_version = int(version_code)
	
	version_nodes.sort_custom(func(first: Node, second: Node) -> bool:
		return int(first.name) < int(second.name))
	
	if not version_nodes.is_empty():
		for node: Node in version_nodes:
			%Versions.add_child(node)
			%Versions.move_child(node, 0)
		var newest_label: Label = %Versions.get_child(0).get_node(^"%VersionName")
		newest_label.text = "Новейшая " + newest_label.text
	
	var highest_installed_version: int = -1
	for installed_version: String in _launcher.versions_file.get_sections():
		if int(installed_version) > highest_installed_version:
			highest_installed_version = int(installed_version)
	
	print("Highest remote version: %d, highest installed version: %d." % [
		highest_version,
		highest_installed_version
	])
	if not update_showed and highest_version > highest_installed_version \
			and _launcher.settings_file.get_value("settings", "updates"):
		update_showed = true
		var version_code: String = str(highest_version)
		var engine_version: String = remote_versions.get_value(version_code, "engine_version")
		var beta: bool = remote_versions.get_value(version_code, "beta")
		_launcher.show_update(version_code, engine_version, beta)


func _clear_versions() -> void:
	for child: Node in %Versions.get_children():
		if child.name == &"Status":
			continue
		%Versions.remove_child(child)
		child.queue_free()


func _download_version_confirm(version_code: String, engine_version: String) -> void:
	var dd: ConfirmationDialog = $DownloadDialog
	dd.dialog_text = "Скачать версию %s?" % remote_versions.get_value(version_code, "name")
	dd.confirmed.connect(_download_version.bind(version_code, engine_version), CONNECT_ONE_SHOT)
	dd.popup_centered()


func _download_version(version_code: String, engine_version: String) -> void:
	hide()
	(_launcher.get_node(^"Downloader") as Downloader).download_version(version_code, engine_version)


func _on_versions_http_request_request_completed(result: HTTPRequest.Result, 
		response_code: HTTPClient.ResponseCode, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Get versions: result (%d) is not Success!" % result)
		return
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Get versions: response code (%d) is not 200!" % response_code)
		return
	
	var err: Error = remote_versions.parse(body.get_string_from_utf8())
	if err != OK:
		push_error("Can't parse remote_versions.cfg. Error: %s." % error_string(err))
		_status.text = "Неправильный формат списка версий."
		_update_button.disabled = false
		return
	for version_code: String in remote_versions.get_sections():
		if not (
				version_code.is_valid_int()
				and remote_versions.has_section_key(version_code, "name")
				and typeof(remote_versions.get_value(version_code, "name")) == TYPE_STRING
				and remote_versions.has_section_key(version_code, "engine_version")
				and typeof(remote_versions.get_value(version_code, "engine_version")) == TYPE_STRING
				and remote_versions.has_section_key(version_code, "platforms")
				and typeof(remote_versions.get_value(version_code, "platforms")) == TYPE_ARRAY
				and remote_versions.has_section_key(version_code, "beta")
				and typeof(remote_versions.get_value(version_code, "beta")) == TYPE_BOOL
		):
			push_error("Incorrent remote_versions.cfg.")
			_status.text = "Неправильный формат списка версий."
			_update_button.disabled = false
			return
	
	err = _engine_versions_http.request(
			_launcher.get_server_url().path_join("remote_engine_versions.cfg")
	)
	if err != OK:
		push_error("Can't download remote_engine_versions.cfg. Error: %s." % error_string(err))
		_status.text = "Ошибка скачивания списка версий движка: %s!" % error_string(err)
		_update_button.disabled = false


func _on_engine_versions_http_request_request_completed(result: HTTPRequest.Result, 
		response_code: HTTPClient.ResponseCode, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Get engine versions: result (%d) is not Success!" % result)
		return
	if response_code != HTTPClient.RESPONSE_OK:
		push_error("Get engine versions: response code (%d) is not 200!" % response_code)
		return
	
	var err: Error = remote_engine_versions.parse(body.get_string_from_utf8())
	if err != OK:
		push_error("Can't parse remote_engine_versions.cfg. Error: %s." % error_string(err))
		_status.text = "Неправильный формат списка версий движка."
		_update_button.disabled = false
		return
	for version: String in remote_engine_versions.get_sections():
		if not (
				remote_engine_versions.has_section_key(version, "editions")
				and typeof(remote_engine_versions.get_value(version, "editions")) == TYPE_ARRAY
		):
			push_error("Incorrent remote_engine_versions.cfg.")
			_status.text = "Неправильный формат списка версий движка."
			_update_button.disabled = false
			return
	
	versions_downloaded = true
	_update_button.disabled = false
	_status.hide()
	print("Downloaded remote configs.")
	list_remote_versions()


func _on_download_dialog_canceled() -> void:
	($DownloadDialog as AcceptDialog).confirmed.disconnect(_download_version)
