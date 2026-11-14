# Stealth and horror: seeing without being seen, scale, tension, and cinematic side-on worlds

**Fear comes from helplessness and from not knowing.** The player must be weaker than what hunts them, able to see it coming, and able to hide. Gore and darkness alone are not tension.

**Stealth rules the player can read:**
- **Sight:** a cone by angle and distance, checked by a ray so walls block it. Show it (a light or a lit floor), since fair hiding needs it.
- **Sound:** running makes noise, which draws the enemy to where it was heard, not to the player.
- **Hiding:** under tables, in lockers, behind objects, in shadow. Being found should be the player's error, understood at once.
```gdscript
func can_see(eye: Node3D, target: Vector3, reach: float, half_angle: float) -> bool:
	var to := target - eye.global_position
	if to.length() > reach or (-eye.global_basis.z).angle_to(to) > half_angle:
		return false
	var hit := eye.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye.global_position, target))
	return hit.is_empty() or hit.collider.is_in_group("player")
```

**Enemy states:** patrol a route → hear (go and look) → suspect (a slow search with a visible alert) → chase (faster than walking, slower than running) → lost you (searches, then returns). The transitions are what the player learns and plays with. Give warning with sound first.

**The cinematic side-on form** (a tiny character in a huge world seen from the side like a diorama):
- Keep the camera on a rail beside the player, far enough to show scale, with a slight downward tilt and slow easing. The world has depth (rooms behind rooms), but the player moves mostly along one line plus small depth moves.
- **Scale is the idea:** a chair leg as wide as the player, doors that fill the screen, a huge table to climb. Size the character at about 3 to 5 percent of screen height. Build furniture at real sizes around a very small player.
- **Silhouettes:** the player and threats read as black shapes against lighter fog or a lit doorway. Give the player one small bright accent, such as a coloured coat, so they are always found at a glance.
- **Light is the path:** dark rooms with one warm pool, or a lighter corridor beyond. Leave large parts of the screen nearly black: dim is not the same as low contrast.
- **Enemies are large and slow, with wrong proportions:** long arms, a heavy head. Their size is the threat.
- **Puzzles are physical:** drag a box, climb a shelf, hide inside a suitcase, wait for a footstep to pass. Almost no interface.
- **Sound:** floorboards, distant breathing, and silence until danger; music only in a chase.
See `style_moody3d` for how to get this look.

**Pacing:** tension needs release. Alternate quiet exploring, a set piece, and a safe room, with something strange happening where nothing can hurt. A chase should be short and scripted enough to feel narrow.

**Death and retry:** a checkpoint just before the challenge, a brief scene, no long reload.

**Touch:** a stick plus one context button (grab, hide, climb) that names what it will do. Hold to run, because running is a decision.

**Make it yours.** A monster who is blind. Hiding by mimicking furniture. Stealth in a supermarket after closing. Escaping from a giant's dinner party. The stranger the premise, the stronger the dread.
