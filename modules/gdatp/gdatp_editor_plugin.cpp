/**************************************************************************/
/*  gdatp_editor_plugin.cpp                                               */
/**************************************************************************/

#include "gdatp_editor_plugin.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/object/class_db.h"
#include "core/object/script_language.h"
#include "core/os/os.h"
#include "editor/doc/doc_tools.h"
#include "editor/doc/editor_help.h"
#include "editor/docks/filesystem_dock.h"
#include "editor/export/editor_export.h"
#include "editor/export/editor_export_platform.h"
#include "editor/editor_data.h"
#include "editor/editor_node.h"
#include "editor/editor_undo_redo_manager.h"
#include "editor/script/script_editor_base.h"
#include "modules/gdscript/gdscript.h"
#include "servers/rendering/rendering_server.h"
#include "servers/rendering/shader_language.h"
#include "servers/rendering/shader_preprocessor.h"
#include "servers/rendering/shader_types.h"
#include "servers/rendering/shader_warnings.h"

void GDatpEditorPlugin::_start_host() {
	if (!Engine::get_singleton()->has_singleton("GDatp")) {
		return;
	}
	Object *bridge = Engine::get_singleton()->get_singleton_object("GDatp");
	const String source = bridge->call("hostSource");
	ERR_FAIL_COND_MSG(source.is_empty(), "GDatp: the tool host's source is missing from the APK.");

	Ref<Script> script = Object::cast_to<Script>(ClassDB::instantiate("GDScript"));
	ERR_FAIL_COND(script.is_null());
	script->set_source_code(source);
	ERR_FAIL_COND_MSG(script->reload() != OK, "GDatp: the tool host's GDScript did not compile.");

	Node *host = memnew(Node);
	host->set_name("GDatpHost");
	host->set_script(script);
	add_child(host);
}

bool GDatpEditorPlugin::undo_scene_step() {
	EditorUndoRedoManager *manager = EditorUndoRedoManager::get_singleton();
	const int history_id = EditorNode::get_editor_data().get_current_edited_scene_history_id();
	UndoRedo *history = manager->get_history_undo_redo(history_id);
	if (history == nullptr || !history->has_undo()) {
		return false;
	}
	return manager->undo_history(history_id);
}

bool GDatpEditorPlugin::redo_scene_step() {
	EditorUndoRedoManager *manager = EditorUndoRedoManager::get_singleton();
	const int history_id = EditorNode::get_editor_data().get_current_edited_scene_history_id();
	UndoRedo *history = manager->get_history_undo_redo(history_id);
	if (history == nullptr || !history->has_redo()) {
		return false;
	}
	return manager->redo_history(history_id);
}

PackedStringArray GDatpEditorPlugin::node_warnings(Object *p_node) const {
	const Node *node = Object::cast_to<Node>(p_node);
	ERR_FAIL_NULL_V(node, PackedStringArray());
	return node->get_configuration_warnings();
}

Dictionary GDatpEditorPlugin::script_tab(Object *p_tab) const {
	Dictionary tab;
	ScriptEditorBase *editor = Object::cast_to<ScriptEditorBase>(p_tab);
	ERR_FAIL_NULL_V(editor, tab);
	const Ref<Resource> edited = editor->get_edited_resource();
	if (edited.is_valid()) {
		tab["path"] = edited->get_path();
		tab["unsaved"] = editor->is_unsaved();
	}
	return tab;
}

Dictionary GDatpEditorPlugin::class_doc(const String &p_class) const {
	DocTools *docs = EditorHelp::get_doc_data();
	ERR_FAIL_NULL_V(docs, Dictionary());
	const DocData::ClassDoc *doc = docs->class_list.getptr(p_class);
	return doc == nullptr ? Dictionary() : DocData::ClassDoc::to_dict(*doc);
}

PackedStringArray GDatpEditorPlugin::doc_class_names() const {
	PackedStringArray names;
	DocTools *docs = EditorHelp::get_doc_data();
	ERR_FAIL_NULL_V(docs, names);
	for (const KeyValue<String, DocData::ClassDoc> &entry : docs->class_list) {
		names.push_back(entry.key);
	}
	names.sort();
	return names;
}

Array GDatpEditorPlugin::check_gdscript(const String &p_source, const String &p_path) const {
	Array found;
	ScriptLanguage *language = ScriptServer::get_language_for_extension("gd");
	ERR_FAIL_NULL_V(language, found);
	List<ScriptLanguage::ScriptError> errors;
	List<ScriptLanguage::Warning> warnings;
	language->validate(p_source, p_path, nullptr, &errors, &warnings);
	for (const ScriptLanguage::ScriptError &error : errors) {
		Dictionary entry;
		entry["kind"] = "error";
		entry["line"] = error.line;
		entry["column"] = error.column;
		entry["message"] = error.message;
		// An error in a script this one depends on names that script.
		if (!error.path.is_empty() && error.path != p_path) {
			entry["path"] = error.path;
		}
		found.push_back(entry);
	}
	for (const ScriptLanguage::Warning &warning : warnings) {
		Dictionary entry;
		entry["kind"] = "warning";
		entry["line"] = warning.start_line;
		entry["code"] = warning.string_code;
		entry["message"] = warning.message;
		found.push_back(entry);
	}
	return found;
}

namespace {

ShaderLanguage::DataType global_shader_uniform_type(const StringName &p_variable) {
	const RSE::GlobalShaderParameterType type = RS::get_singleton()->global_shader_parameter_get_type(p_variable);
	return (ShaderLanguage::DataType)RS::global_shader_uniform_type_get_shader_datatype(type);
}

RSE::ShaderMode shader_mode_of(const String &p_type) {
	if (p_type == "canvas_item") {
		return RSE::SHADER_CANVAS_ITEM;
	} else if (p_type == "particles") {
		return RSE::SHADER_PARTICLES;
	} else if (p_type == "sky") {
		return RSE::SHADER_SKY;
	} else if (p_type == "fog") {
		return RSE::SHADER_FOG;
	} else if (p_type == "texture_blit") {
		return RSE::SHADER_TEXTURE_BLIT;
	}
	return RSE::SHADER_SPATIAL;
}

Dictionary shader_problem(const String &p_kind, int p_line, const String &p_message) {
	Dictionary entry;
	entry["kind"] = p_kind;
	entry["line"] = p_line;
	entry["message"] = p_message;
	return entry;
}

} // namespace

Array GDatpEditorPlugin::check_shader(const String &p_source, const String &p_path) const {
	Array found;
	ShaderPreprocessor preprocessor;
	String code;
	String preprocess_error;
	List<ShaderPreprocessor::FilePosition> positions;
	if (preprocessor.preprocess(p_source, p_path, code, &preprocess_error, &positions) != OK) {
		found.push_back(shader_problem("error", positions.is_empty() ? 0 : positions.front()->get().line, preprocess_error));
		return found;
	}

	ShaderLanguage language;
	language.enable_warning_checking(GLOBAL_GET("debug/shader_language/warnings/enable").booleanize());
	HashMap<ShaderWarning::Code, bool> warnings_on;
	for (int i = 0; i < ShaderWarning::WARNING_MAX; i++) {
		const ShaderWarning::Code warning = (ShaderWarning::Code)i;
		warnings_on[warning] = GLOBAL_GET("debug/shader_language/warnings/" + ShaderWarning::get_name_from_code(warning).to_lower()).booleanize();
	}
	const bool include = p_path.get_extension() == "gdshaderinc";
	uint32_t flags = ShaderWarning::get_flags_from_codemap(warnings_on);
	if (include) {
		// An include's declarations are used by the shaders that include it, so it is not told they are unused.
		flags &= ~(ShaderWarning::UNUSED_CONSTANT_FLAG | ShaderWarning::UNUSED_FUNCTION_FLAG | ShaderWarning::UNUSED_STRUCT_FLAG |
				ShaderWarning::UNUSED_UNIFORM_FLAG | ShaderWarning::UNUSED_VARYING_FLAG);
	}
	language.set_warning_flags(flags);

	ShaderLanguage::ShaderCompileInfo info;
	info.global_shader_uniform_type_func = global_shader_uniform_type;
	if (include) {
		info.is_include = true;
	} else {
		const RSE::ShaderMode mode = shader_mode_of(ShaderLanguage::get_shader_type(p_source));
		info.functions = ShaderTypes::get_singleton()->get_functions(mode);
		info.render_modes = ShaderTypes::get_singleton()->get_modes(mode);
		info.stencil_modes = ShaderTypes::get_singleton()->get_stencil_modes(mode);
		info.shader_types = ShaderTypes::get_singleton()->get_types();
	}
	if (language.compile(code, info) != OK) {
		found.push_back(shader_problem("error", language.get_error_line(), language.get_error_text()));
	}
	for (List<ShaderWarning>::Element *E = language.get_warnings_ptr(); E; E = E->next()) {
		found.push_back(shader_problem("warning", E->get().get_line(), E->get().get_message()));
	}
	return found;
}

void GDatpEditorPlugin::_watch_exec(void *p_self) {
	GDatpEditorPlugin *self = static_cast<GDatpEditorPlugin *>(p_self);
	while (!self->exec_finished.is_set()) {
		if (OS::get_singleton()->get_ticks_msec() >= self->exec_deadline_msec) {
			self->exec_stopped.set();
			GDScriptLanguage::get_singleton()->interrupt_loops_of(Object::cast_to<GDScript>(self->exec_script.ptr()));
			return;
		}
		OS::get_singleton()->delay_usec(20000);
	}
}

void GDatpEditorPlugin::watch_exec(const Ref<Script> &p_script, double p_seconds) {
	ERR_FAIL_COND(p_script.is_null());
	end_exec_watch();
	exec_script = p_script;
	exec_finished.clear();
	exec_stopped.clear();
	exec_deadline_msec = OS::get_singleton()->get_ticks_msec() + uint64_t(MAX(p_seconds, 0.0) * 1000.0);
	exec_watch.start(_watch_exec, this);
}

bool GDatpEditorPlugin::end_exec_watch() {
	exec_finished.set();
	if (exec_watch.is_started()) {
		exec_watch.wait_to_finish();
	}
	GDScriptLanguage::get_singleton()->interrupt_loops_of(nullptr);
	exec_script.unref();
	return exec_stopped.is_set();
}

Dictionary GDatpEditorPlugin::move_path(const String &p_from, const String &p_to) {
	Vector<String> updated;
	FileSystemDock *dock = FileSystemDock::get_singleton();
	Dictionary answer;
	answer["error"] = dock != nullptr ? dock->move_path(p_from, p_to, updated) : ERR_UNAVAILABLE;
	answer["updated"] = PackedStringArray(updated);
	return answer;
}

void GDatpEditorPlugin::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		_start_host();
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		end_exec_watch();
	}
}

Dictionary GDatpEditorPlugin::export_android(const Dictionary &p_settings, const String &p_path, const String &p_exclude) {
	Dictionary answer;
	Array messages;
	EditorExport *exporter = EditorExport::get_singleton();
	const int index = exporter->get_export_platform_index_by_name("Android");
	if (index < 0) {
		answer["error"] = int(ERR_UNAVAILABLE);
		messages.push_back("This editor has no Android exporter.");
		answer["messages"] = messages;
		return answer;
	}
	Ref<EditorExportPlatform> platform = exporter->get_export_platform(index);
	Ref<EditorExportPreset> preset = platform->create_preset();
	preset->set_name("GDatp");
	preset->set_exclude_filter(p_exclude);
	preset->set_export_path(p_path);
	for (const KeyValue<Variant, Variant> &setting : p_settings) {
		preset->set(setting.key, setting.value);
	}
	platform->clear_messages();
	const Error error = platform->export_project(preset, false, p_path, 0);
	for (int i = 0; i < platform->get_message_count(); i++) {
		const EditorExportPlatform::ExportMessage message = platform->get_message(i);
		messages.push_back(message.category + ": " + message.text);
	}
	answer["error"] = int(error);
	answer["messages"] = messages;
	return answer;
}

void GDatpEditorPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("export_android", "settings", "path", "exclude"), &GDatpEditorPlugin::export_android);
	ClassDB::bind_method(D_METHOD("undo_scene_step"), &GDatpEditorPlugin::undo_scene_step);
	ClassDB::bind_method(D_METHOD("redo_scene_step"), &GDatpEditorPlugin::redo_scene_step);
	ClassDB::bind_method(D_METHOD("node_warnings", "node"), &GDatpEditorPlugin::node_warnings);
	ClassDB::bind_method(D_METHOD("script_tab", "tab"), &GDatpEditorPlugin::script_tab);
	ClassDB::bind_method(D_METHOD("class_doc", "class_name"), &GDatpEditorPlugin::class_doc);
	ClassDB::bind_method(D_METHOD("doc_class_names"), &GDatpEditorPlugin::doc_class_names);
	ClassDB::bind_method(D_METHOD("check_gdscript", "source", "path"), &GDatpEditorPlugin::check_gdscript);
	ClassDB::bind_method(D_METHOD("check_shader", "source", "path"), &GDatpEditorPlugin::check_shader);
	ClassDB::bind_method(D_METHOD("watch_exec", "script", "seconds"), &GDatpEditorPlugin::watch_exec);
	ClassDB::bind_method(D_METHOD("end_exec_watch"), &GDatpEditorPlugin::end_exec_watch);
	ClassDB::bind_method(D_METHOD("move_path", "from", "to"), &GDatpEditorPlugin::move_path);
}
