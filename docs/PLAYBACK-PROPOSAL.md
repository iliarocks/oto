# Source, repeat, and consumable queue behavior

The album being played is the stable playback source. Explicit additions form a separate, temporary queue that runs before the remaining source tracks.

## Starting and adding music

- Play on a different album starts its first track immediately and replaces the source. Pending manual additions survive; a currently playing manual entry is consumed when left.
- Play/Pause on the active source album toggles the current playback session, preserving position and additions. A queued song from another album does not make that other album the active source.
- Selecting a song in an album starts the source at that song, retaining earlier source tracks for Previous and repeat.
- Add to Queue appends after other pending manual additions, before the source remainder. Adding an album preserves its track order. If playback is paused, adding leaves it paused. With nothing loaded, an addition starts playback without establishing an album source.
- Duplicate additions have distinct identities and can be edited independently.

Example: while playing Dusk, add Care and then a Takeo Ōnuki song. Playback proceeds Dusk → Care → Takeo song → The Last Dance → the remaining Lamp tracks. Once left, the manual entries disappear from the session rather than becoming source history.

## Next, Previous, and repeat

Next starts playback even when previously paused. A successful manual Next changes Repeat One to Repeat All. Selecting an upcoming entry also starts playback and exits Repeat One; entries passed over in the manual queue are consumed.

Previous follows the source sequence:

| State | Previous action | Repeat mode |
| --- | --- | --- |
| Paused, position greater than zero | Reset the current song to zero; stay paused | Unchanged |
| Paused at zero | Move to the previous source song and play | One becomes All only if a track changes |
| Playing, more than three seconds in | Restart the current song and keep playing | Unchanged |
| Playing, near the start | Move to the previous source song and play | One becomes All only if a track changes |

Near the start of a manual entry, Previous consumes that entry and returns to the most recent source song; remaining manual additions stay pending. At the beginning of the source, or with no source, Previous restarts the current song without changing the repeat mode or starting a paused song. Returning from a manual detour does not recreate consumed entries. After returning from The Last Dance to Dusk, Next goes to The Last Dance unless there are still pending manual additions.

- Repeat Off stops after the source and pending additions end.
- Repeat All cycles the source only, including its edited order. Manual additions play once. A queue without a source does not loop under Repeat All.
- Repeat One repeats the current song on natural completion, including a manual entry, until the user leaves it.
- An unavailable song stops with the existing error; repeat never creates an automatic error/retry loop.

## Queue view and editing

Keep the accepted artwork-to-queue transition and fixed transport controls. The queue view separates Queued from Next from [album]. Clear removes pending manual additions only. Reorder and remove entries within each section; removing a source entry also removes it from subsequent repeat cycles. Reordering never interrupts audio. Swiping a song or album offers the existing icon-only Add to Queue action; queued rows retain icon-only removal.

## Restoration

Save the source, its position, the active entry, pending manual additions, repeat mode, folder, and elapsed time. Restore paused without opening audio. Previous must also reset an unloaded restored song correctly. Refresh updates surviving entries and preserves the source resume point; replacing a removed current song remains paused. Switching folders clears playback.

The prior flat saved queue contains no source/manual provenance. Preserve its current entry and remaining order as a legacy source until an album is selected, rather than guessing which entries the user added. New saves contain explicit source and manual state.
