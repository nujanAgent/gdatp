/**************************************************************************/
/*  gdatp_game_helper.h                                                   */
/**************************************************************************/

#pragma once

// In a game the editor started, takes the editor's "gdatp:" debugger messages: "helper" carries the game helper's
// GDScript, which is compiled and added to the game, "call" hands a tool call to it, and "input" presses actions and
// switches input on for a frame that stepping lets through. All are obeyed only with the run's token, because any app
// on the phone can reach the debugger's port: the helper is admitted with the token the editor writes to GDatp's
// private cache once this game connects, and the other messages must carry that same token for the rest of the run.
void gdatp_start_game_helper();

// Notes when this process began. Called before the debugger connects, so a token written for this game is newer.
void gdatp_note_process_start();
