class_name Settings
extends Window

const DEFAULT_ARGUMENTS := "--disable-update-check"
const DEFAULT_SERVER := "https://diamond-studio-games.github.io/circle-shot"
@onready var _launcher: Launcher = get_parent()

func _ready() -> void:
	var updates: bool = _launcher.settings_file.get_value("settings", "updates", true)
	var betas: bool = _launcher.settings_file.get_value("settings", "betas", false)
	var beta_updates: bool = _launcher.settings_file.get_value("settings", "beta_updates", false)
	_launcher.settings_file.set_value("settings", "updates", updates)
	_launcher.settings_file.set_value("settings", "betas", betas)
	_launcher.settings_file.set_value("settings", "beta_updates", beta_updates)
	(%UpdatesCheck as BaseButton).set_pressed_no_signal(updates)
	(%BetasCheck as BaseButton).set_pressed_no_signal(betas)
	(%BetaUpdatesCheck as BaseButton).set_pressed_no_signal(beta_updates)
	_update_beta_updates_visibility()
	
	var arguments: String = \
			_launcher.settings_file.get_value("settings", "arguments", DEFAULT_ARGUMENTS)
	var server: String = _launcher.settings_file.get_value("settings", "server", DEFAULT_SERVER)
	_launcher.settings_file.set_value("settings", "arguments", arguments)
	_launcher.settings_file.set_value("settings", "server", server)
	(%ArgumentsEdit as LineEdit).text = arguments
	(%ServerEdit as LineEdit).text = server


func _update_beta_updates_visibility() -> void:
	(%ShowBetaUpdates as CanvasItem).visible = (%UpdatesCheck as BaseButton).button_pressed \
			and (%BetasCheck as BaseButton).button_pressed
	if not (%ShowBetaUpdates as CanvasItem).visible:
		_launcher.settings_file.set_value("settings", "beta_updates", false)
		_launcher.save_files()


func _on_updates_check_toggled(toggled_on: bool) -> void:
	_launcher.settings_file.set_value("settings", "updates", toggled_on)
	_launcher.save_files()
	_update_beta_updates_visibility()


func _on_betas_check_toggled(toggled_on: bool) -> void:
	_launcher.settings_file.set_value("settings", "betas", toggled_on)
	_launcher.save_files()
	_update_beta_updates_visibility()
	(_launcher.get_node(^"RemoteManager") as RemoteManager).list_remote_versions()


func _on_beta_updates_check_toggled(toggled_on: bool) -> void:
	_launcher.settings_file.set_value("settings", "beta_updates", toggled_on)
	_launcher.save_files()


func _on_arguments_edit_text_changed(new_text: String) -> void:
	_launcher.settings_file.set_value("settings", "arguments", new_text)
	_launcher.save_files()


func _on_server_edit_text_changed(new_text: String) -> void:
	_launcher.settings_file.set_value("settings", "server", new_text)
	_launcher.save_files()


func _on_open_data_path_pressed() -> void:
	OS.shell_show_in_file_manager(_launcher.data_path)
