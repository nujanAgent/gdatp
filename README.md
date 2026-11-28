# GDatp

GDatp is a fork of the [Godot Engine](https://godotengine.org) editor for Android. It is Godot's own Android editor,
built from Godot's source with a small set of changes that let an AI agent app, such as NuJan, work in the same editor
as you: open and create projects, read and edit scenes, scripts and resources, run the game, press its inputs and look
at it. The agent reaches the editor through ATP (App Tools Protocol), only after you allow it on GDatp's own screen,
and only for the groups of tools you turn on.

GDatp is not affiliated with or endorsed by the Godot Foundation. "Godot" and the Godot logo are trademarks of the
Godot Foundation; GDatp has its own name and icon.

- **Based on:** Godot `4.7.2-stable` (`ed1daf0`). This repository holds the files GDatp adds to Godot or changes, and
  `gdatp/tools/apply_to_godot.sh` puts them over that release.
- **Package:** `com.gd.atp`, so it installs beside Godot's own editor.
- **Distributed here,** on GitHub, not on Google Play.

## What it adds to the editor

- Tools an agent can call, each with several actions: projects, files and resources, scenes and nodes, scripts and
  their errors, animation, tile maps, user interfaces, 3D, running the game, input steps, screenshots, logs and undo.
  What each does is in [GDATP.md](GDATP.md).
- A connection screen where you allow an app, and a screen of connected apps where you choose what each may use. Code
  that an agent writes and runs inside the editor ("Run any code") stays off unless you turn it on in GDatp yourself.
- Its own name and look: launcher icon, start-up screen, About box and logos, with Godot's credits and licences kept in
  full ([GDATP.md](GDATP.md#its-own-name-and-look)).

Everything else is Godot's editor as Godot ships it.

## Install

1. Download the APK from the latest [release](https://github.com/nujanAgent/gdatp/releases) and check it against the
   SHA-256 and the signing certificate's fingerprint the release lists.
2. Open it on the phone and allow the install.

[Obtainium](https://github.com/ImranR98/Obtainium) can follow this repository's releases: add
`https://github.com/nujanAgent/gdatp` as an app.

## Build from source

First make the source tree: `sh gdatp/tools/apply_to_godot.sh <new folder>` clones Godot `4.7.2-stable` into the
folder, checks it is commit `ed1daf0`, and copies GDatp's files over it, checking each against
`gdatp/overlay.sha256`. It needs git and a network connection to GitHub.

The build is Godot's Android editor build, with GDatp's checks first, run in that folder. You need the Android SDK
(NDK `29.0.14206865`, build-tools `36.1.0`, platform 36), JDK 17, and Python 3 with SCons 4. The steps are in
[GDATP.md](GDATP.md), "Building".

## Reporting a problem

- A problem with GDatp's tools, its connection screens or its build: open an issue
  [here](https://github.com/nujanAgent/gdatp/issues).
- A problem that Godot's own editor has too: report it to Godot at https://github.com/godotengine/godot/issues.
- A security problem: see [SECURITY.md](SECURITY.md).

## Licence

Godot is under the MIT licence ([LICENSE.txt](LICENSE.txt)), and so are GDatp's changes. The third-party software in
the engine and in GDatp, with each licence, is listed in [COPYRIGHT.txt](COPYRIGHT.txt). [PRIVACY.md](PRIVACY.md) says
what GDatp does with your data, and [TERMS.md](TERMS.md) how it may be used.
