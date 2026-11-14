/**************************************************************************/
/*  gdatp_game_helper.cpp                                                 */
/**************************************************************************/

#include "gdatp_game_helper.h"

#include "core/debugger/engine_debugger.h"
#include "core/input/input.h"
#include "core/input/input_map.h"
#include "core/io/file_access.h"
#include "core/object/class_db.h"
#include "core/object/script_language.h"
#include "core/os/os.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

namespace {

// When this process began, in whole seconds, noted before its debugger connects to the editor.
uint64_t process_started_s = 0;

ObjectID helper_id;
// The token the helper was admitted with; every call during this run carries it, however long the run lasts.
String run_token;

// The editor writes a run's token once the game connects, so a token file older than this process was left by an
// earlier run and is refused, while a game that takes long to reach its first frame still has its own run's token.
bool token_is_fresh(const Variant &p_token) {
	const String path = OS::get_singleton()->get_cache_path().path_join("gdatp/run-token");
	Ref<FileAccess> file = FileAccess::open(path, FileAccess::READ);
	if (file.is_null()) {
		return false;
	}
	const String expected = file->get_as_text().strip_edges();
	const bool written_since_start = FileAccess::get_modified_time(path) >= process_started_s;
	return !expected.is_empty() && p_token.get_type() == Variant::STRING && String(p_token) == expected && written_since_start;
}

bool carries_run_token(const Variant &p_token) {
	return !run_token.is_empty() && p_token.get_type() == Variant::STRING && String(p_token) == run_token;
}

void reply(const Variant &p_id, const String &p_answer_json) {
	Array data;
	data.push_back(p_id);
	data.push_back(p_answer_json);
	EngineDebugger::get_singleton()->send_message("gdatp:reply", data);
}

Error capture(void *p_user, const String &p_message, const Array &p_args, bool &r_captured) {
	r_captured = true;
	if (p_message == "helper") {
		ERR_FAIL_COND_V(p_args.size() != 2, ERR_INVALID_PARAMETER);
		ERR_FAIL_COND_V_MSG(!token_is_fresh(p_args[0]), ERR_UNAUTHORIZED, "GDatp: a game helper was offered without the run's token.");
		run_token = p_args[0];
		if (ObjectDB::get_instance(helper_id) != nullptr) {
			EngineDebugger::get_singleton()->send_message("gdatp:ready", Array());
			return OK;
		}
		Ref<Script> script = Object::cast_to<Script>(ClassDB::instantiate("GDScript"));
		ERR_FAIL_COND_V(script.is_null(), ERR_UNAVAILABLE);
		script->set_source_code(p_args[1]);
		ERR_FAIL_COND_V_MSG(script->reload() != OK, ERR_PARSE_ERROR, "GDatp: the game helper's GDScript did not compile.");
		Node *helper = memnew(Node);
		helper->set_name("GDatpGameHelper");
		helper->set_process_mode(Node::PROCESS_MODE_ALWAYS);
		helper->set_script(script);
		helper_id = helper->get_instance_id();
		SceneTree::get_singleton()->get_root()->call_deferred(SNAME("add_child"), helper);
		return OK;
	}
	if (p_message == "call") {
		ERR_FAIL_COND_V(p_args.size() != 4, ERR_INVALID_PARAMETER);
		if (!carries_run_token(p_args[0])) {
			// Answered, so the editor reports it at once instead of waiting out its limit.
			reply(p_args[1], "{\"error\":\"wrong_token\",\"message\":\"The game refused a call without its run's token; run restart starts a fresh run.\"}");
			ERR_FAIL_V_MSG(ERR_UNAUTHORIZED, "GDatp: a tool call reached the game without the run's token.");
		}
		Node *helper = Object::cast_to<Node>(ObjectDB::get_instance(helper_id));
		if (helper == nullptr) {
			reply(p_args[1], "{\"error\":\"no_helper\",\"message\":\"The game helper is not running in this game.\"}");
			return OK;
		}
		helper->call_deferred(SNAME("handle"), p_args[1], p_args[2], p_args[3]);
		return OK;
	}
	if (p_message == "input") {
		// Sent before each frame `run step` lets through. Suspending a game switches its input off and stepping does not
		// switch it back on, so without this a held action never reaches a stepped frame. Actions pressed here, between
		// frames, count as just pressed in the next one; pausing again switches input off.
		ERR_FAIL_COND_V(p_args.size() != 3, ERR_INVALID_PARAMETER);
		ERR_FAIL_COND_V_MSG(!carries_run_token(p_args[0]), ERR_UNAUTHORIZED, "GDatp: input reached the game without the run's token.");
		Input *input = Input::get_singleton();
		const Array presses = p_args[1];
		for (const Variant &action : presses) {
			if (InputMap::get_singleton()->has_action(action)) {
				input->action_press(action);
			}
		}
		const Array releases = p_args[2];
		for (const Variant &action : releases) {
			if (InputMap::get_singleton()->has_action(action)) {
				input->action_release(action);
			}
		}
		input->set_disable_input(false);
		return OK;
	}
	r_captured = false;
	return ERR_SKIP;
}

} // namespace

void gdatp_note_process_start() {
	process_started_s = (uint64_t)OS::get_singleton()->get_unix_time();
}

void gdatp_start_game_helper() {
	if (EngineDebugger::is_active()) {
		EngineDebugger::register_message_capture("gdatp", EngineDebugger::Capture(nullptr, capture));
	}
}
