extends RefCounted
## Separate Settings sharing dialog; ordinary Save/Reset remain unchanged.
const SHARE=preload("res://campaigns/prompt_sharing.gd")

static func open(parent: Node,on_change: Callable) -> void:
	var dialog=AcceptDialog.new()
	dialog.title="Narrator prompt handover"
	dialog.get_ok_button().text="Close"
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	var col=VBoxContainer.new()
	col.custom_minimum_size.x=580
	dialog.add_child(col)
	var info=Label.new()
	info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	info.text="Save the Narrator in Settings first. Export only the saved prompt and revision metadata for the Lead. No Git upload occurs. Review for personal information or secrets before sharing."
	col.add_child(info)
	var summary=LineEdit.new()
	summary.placeholder_text="Owner change summary (required)"
	summary.max_length=500
	col.add_child(summary)
	var consent=CheckBox.new()
	consent.text="I have reviewed the saved prompt and authorize this local export."
	col.add_child(consent)
	var export=Button.new()
	export.text="Export prompt-only proposal"
	col.add_child(export)
	export.pressed.connect(func():
		var result=SHARE.export_proposal(summary.text,consent.button_pressed)
		info.text=("Exported locally (not published): "+result["path"]) if result.get("ok",false) else result["error"])
	var import=Button.new()
	import.text="Inspect Lead-approved shared revision"
	col.add_child(import)
	import.pressed.connect(func():
		var picker=FileDialog.new()
		picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		picker.access=FileDialog.ACCESS_FILESYSTEM
		picker.filters=PackedStringArray(["*.json ; Prompt-only JSON"])
		dialog.add_child(picker)
		picker.file_selected.connect(func(path: String):
			var result=SHARE.inspect_shared(path)
			if not result.get("ok",false):
				info.text=result["error"]
			else:
				inspect(dialog,result,on_change)
			picker.queue_free())
		picker.canceled.connect(picker.queue_free)
		picker.popup_centered(Vector2i(800,550)))
	dialog.popup_centered(Vector2i(640,310))

static func inspect(parent: Node,preview: Dictionary,on_change: Callable) -> void:
	var dialog=AcceptDialog.new()
	dialog.title="Review shared Narrator revision"
	dialog.get_ok_button().text="Close without changes"
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	var col=VBoxContainer.new()
	dialog.add_child(col)
	var note=Label.new()
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var bundle=preview["bundle"]
	note.text="Revision "+str(bundle["revision"])+" · "+bundle["source_commit"]+"\n"+bundle["summary"]+"\n"+("Conflict: both local and shared prompt changed." if preview["conflict"] else "Base matches.")+"\nVerify the Lead approved this source commit before accepting."
	col.add_child(note)
	var row=HBoxContainer.new()
	col.add_child(row)
	for pair in [["Current local",preview["local_prompt"]],["Incoming shared",bundle["prompt"]]]:
		var panel=VBoxContainer.new()
		row.add_child(panel)
		var title=Label.new()
		title.text=pair[0]
		panel.add_child(title)
		var content=TextEdit.new()
		content.editable=false
		content.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
		content.custom_minimum_size=Vector2(380,300)
		content.text=pair[1]
		panel.add_child(content)
	var confirm=CheckBox.new()
	confirm.text="I verified the shared revision and reviewed both versions."
	col.add_child(confirm)
	for option in [["Record shared base; keep local prompt",false],["Record shared base; replace local prompt",true]]:
		var use_remote=option[1]
		var button=Button.new()
		button.text=option[0]
		col.add_child(button)
		button.pressed.connect(func():
			var result=SHARE.apply_shared(preview,use_remote,confirm.button_pressed)
			note.text=result.get("message",result.get("error","Import failed."))
			if result.get("ok",false) and on_change.is_valid():
				on_change.call())
	dialog.popup_centered(Vector2i(820,510))
