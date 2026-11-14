/**************************************************************************/
/*  gdatp_editor_plugin.h                                                 */
/**************************************************************************/

#pragma once

#include "core/os/thread.h"
#include "core/templates/safe_refcount.h"
#include "editor/plugins/editor_plugin.h"

// Starts GDatp's tool host in the editor: a node running GDScript that GDatp's Android side supplies, which carries
// out the tools NuJan calls in whichever project is open, without adding files to the project. It also gives the host
// what the editor does not expose to scripts.
class GDatpEditorPlugin : public EditorPlugin {
	GDCLASS(GDatpEditorPlugin, EditorPlugin);

	void _start_host();

	// The time limit on code the host runs in the editor: a thread that marks the code's script once the limit passes.
	Thread exec_watch;
	SafeFlag exec_finished;
	SafeFlag exec_stopped;
	Ref<Script> exec_script;
	uint64_t exec_deadline_msec = 0;
	static void _watch_exec(void *p_self);

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	virtual String get_plugin_name() const override { return "GDatp"; }

	// Undoes or redoes the newest step of the open scene's history the way the editor's own Undo and Redo do, so the
	// editor's record of saved and unsaved changes stays right.
	bool undo_scene_step();
	bool redo_scene_step();

	// The warnings the Scene dock shows for a node, such as a body without a collision shape; scripts can only reach
	// the ones a tool script adds.
	PackedStringArray node_warnings(Object *p_node) const;

	// The file a script editor tab edits, a script or a text file, and whether the tab has changes not yet saved, as
	// {"path", "unsaved"}; empty for a tab without a file. Scripts reach a tab's text, not the file it shows.
	Dictionary script_tab(Object *p_tab) const;

	// This editor's class reference: one class as a dictionary, empty when there is no such class, and every class's name.
	Dictionary class_doc(const String &p_class) const;
	PackedStringArray doc_class_names() const;

	// Every compile error and warning in GDScript source, as the script editor finds them: checked as the file at
	// p_path, so the file's own class_name is not a clash and another file's is. Scripts get only the first error.
	Array check_gdscript(const String &p_source, const String &p_path) const;

	// Shader source checked as the shader editor checks it: the preprocessor, then the compiler for the shader type the
	// code declares (an include, .gdshaderinc, as an include), with the project's warning settings. Each problem as
	// {"kind": "error" or "warning", "line", "message"}.
	Array check_shader(const String &p_source, const String &p_path) const;

	// Puts a time limit on p_script, code the host is about to run: once p_seconds pass, a loop in it ends at its next
	// turn with a script error, so code that never returns does not freeze the editor. A long call into the engine is
	// not cut short. end_exec_watch() lifts the limit and says whether the code was stopped.
	void watch_exec(const Ref<Script> &p_script, double p_seconds);
	bool end_exec_watch();

	// Moves or renames a project file or folder through the FileSystem dock, so the scenes, resources and project
	// settings that refer to it follow it: {"error": the result, "updated": the files whose references were rewritten}.
	Dictionary move_path(const String &p_from, const String &p_to);

	// Exports the open project to an APK with the engine's Android exporter, which signs it on the phone. p_settings are the export
	// preset's options; files matching p_exclude stay out. {"error": the result, "messages": what the exporter said}.
	Dictionary export_android(const Dictionary &p_settings, const String &p_path, const String &p_exclude);
};
