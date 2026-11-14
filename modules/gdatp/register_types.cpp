/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/

#include "register_types.h"

#include "gdatp_game_helper.h"

#include "core/debugger/engine_debugger.h"

#ifdef TOOLS_ENABLED
#include "gdatp_editor_plugin.h"

#include "core/object/class_db.h"
#endif

void initialize_gdatp_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_CORE) {
		// Core modules start before the debugger connects to the editor.
		gdatp_note_process_start();
	}
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		// Only a game the editor started runs with the debugger active.
		gdatp_start_game_helper();
	}
#ifdef TOOLS_ENABLED
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		GDREGISTER_INTERNAL_CLASS(GDatpEditorPlugin);
		EditorPlugins::add_by_type<GDatpEditorPlugin>();
	}
#endif
}

void uninitialize_gdatp_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE && EngineDebugger::is_active()) {
		EngineDebugger::unregister_message_capture("gdatp");
	}
}
