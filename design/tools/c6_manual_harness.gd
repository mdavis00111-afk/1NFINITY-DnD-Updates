extends SceneTree
## Internal test-only entry point. Copy into an isolated archived game project.
## Never installed or wired into production. Explicit local provider opt-in.
const MAIN=preload("res://main.tscn")
const BASE=preload("res://campaigns/campaign_store.gd")
const CTRL=preload("res://gameplay/semantic_controller.gd")
const WORKSPACE=preload("res://gameplay/game_workspace.gd")
var screen: Control
var controller: Node
var allow_provider=false

class OfflineTransport:
	extends Node
	signal completed(ok: bool,message: String)
	var retired=false
	func generate(_prompt: String,_key: String="",_model: String="",_complete: bool=false,_schema: Dictionary={},_chars: int=4000,_tokens: int=2048,_temperature: float=0.8) -> void:
		unavailable.call_deferred()
	func unavailable() -> void:
		if not retired:
			completed.emit(false,"Offline C6 manual harness; provider intentionally disabled.")
	func cancel_generation() -> void:
		retired=true

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var expected=OS.get_environment("INFINITY_TEST_USER_ROOT").replace("\\","/").trim_suffix("/")
	var actual=ProjectSettings.globalize_path("user://").replace("\\","/").trim_suffix("/")
	var profile=str(ProjectSettings.get_setting("application/config/custom_user_dir_name",""))
	if OS.get_environment("INFINITY_C6_MANUAL")!="YES" or expected.is_empty() or expected!=actual or not profile.begins_with("1NFINITY_C6_") or profile.length()!=44 or actual.get_file()!=profile or FileAccess.get_file_as_string("user://.c6-test-profile")!=profile:
		push_error("C6 manual harness refuses non-authorized or non-disposable user root.")
		quit(2)
		return
	allow_provider=OS.get_environment("INFINITY_C6_PROVIDER")=="YES"
	auto_accept_quit=false
	root.close_requested.connect(shutdown)
	var mode=OS.get_environment("INFINITY_C6_MODE")
	if mode=="setup":
		show_setup()
	elif mode=="play":
		show_selector()
	else:
		push_error("Set INFINITY_C6_MODE to setup or play.")
		quit(2)

func clear_screen() -> void:
	if is_instance_valid(controller):
		# Existing instrumentation is numeric/stage-only. No prompts or keys.
		print("C6_SESSION_METRICS ",JSON.stringify({"controller":controller.timing_samples,"provider":controller.adapter.metrics if is_instance_valid(controller.adapter) else []}))
		controller.close_session()
		controller.queue_free()
	controller=null
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
	screen=null

func show_setup() -> void:
	clear_screen()
	screen=MAIN.instantiate()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func button(parent: Container,text: String,action: Callable) -> void:
	var b=Button.new()
	b.text=text
	b.custom_minimum_size.y=38
	b.pressed.connect(action)
	parent.add_child(b)

func show_selector(message: String="") -> void:
	clear_screen()
	screen=Control.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme=load("res://themes/master_theme.tres")
	var outer=MarginContainer.new()
	screen.add_child(outer)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		outer.add_theme_constant_override("margin_"+side,24)
	var content=VBoxContainer.new()
	outer.add_child(content)
	var note=Label.new()
	note.text="C6 INTERNAL QA — disposable profile only\nProvider: "+("explicitly enabled for local testing" if allow_provider else "OFFLINE (requests fail intentionally)")+"\n"+message
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	var scroll=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var rows=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for campaign in BASE.new().list_campaigns():
		var id=str(campaign["id"])
		button(rows,str(campaign["title"])+"  ["+id.left(8)+"]",open_campaign.bind(id))
	button(content,"Exit QA",shutdown)

func open_campaign(id: String) -> void:
	clear_screen()
	controller=CTRL.new()
	root.add_child(controller)
	var factory=Callable()
	if not allow_provider:
		factory=func(): return OfflineTransport.new()
	var bound=controller.bind_ai(id,Callable(),Callable(),factory)
	if not bound.get("ok",false):
		show_selector(str(bound.get("error","Binding failed.")))
		return
	var workspace=WORKSPACE.new()
	var mounted=controller.mount_workspace(workspace,show_selector,show_setup)
	if not mounted.get("ok",false):
		workspace.free()
		show_selector(str(mounted.get("error","Workspace mount failed.")))
		return
	screen=workspace
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func shutdown() -> void:
	clear_screen()
	quit(0)
