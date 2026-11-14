# Privacy

Last updated: 30 October 2026

GDatp has no account, no server of its own and no analytics or crash reporting. Its developer receives nothing from
it.

## What stays on your phone

Your projects, the editor's settings and logs, and the list of connected apps with what each may use. Projects stay
where you keep them; the rest is in GDatp's own storage and is removed with the app.

## What leaves your phone, and when

GDatp starts in Godot's offline mode. Only if you switch **Editor Settings › Network › Network Mode** to Online do the
Asset Library and the download of export templates reach Godot's servers and the hosts of the assets you choose, which
see your IP address under their own privacy policies. A game you build and run can reach the network if its own code
does.

## Connected apps

An app such as NuJan connects to GDatp only after you allow it on GDatp's own screen, and it can use only the groups of
tools you turn on for it: reading your project, changing it, running it, and, only if you turn it on in GDatp yourself,
running code it writes inside the editor. Calls between the two apps stay on the phone. What the connected app does
with the results, screenshots of your game among them, is covered by that app's privacy policy: NuJan, for example,
may send a tool's result to the AI model you chose in NuJan. You can change or end each connection under Connected
apps.

## Permissions

| Permission | Why |
| --- | --- |
| Internet | The Asset Library and export templates when you turn the network on, and games that use the network |
| Microphone, camera | Only for games you run that use them; Android asks you first |
| Vibration | Games that vibrate the phone |
| Install apps | Offers a game you exported as an APK to Android's install screen, where you decide |
| All files access | Opening projects kept in your phone's shared folders; GDatp asks once |

## Reporting a problem

Issues on GitHub are public. Do not post personal data or files that hold it. For a security problem, see
[SECURITY.md](SECURITY.md).

Questions about this policy: open an issue at https://github.com/nujanAgent/gdatp/issues.
