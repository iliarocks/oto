# Repeat and queue behavior

Status: accepted and implemented; validation and device delivery are recorded in WORKLOG.md.

## Where the controls live

- Album pages: one prominent Play/Pause button follows the album artwork accent.
- Now Playing: place smaller queue and repeat controls on either side of the existing previous/play/next controls, with full-sized touch targets. Active modes use the artwork accent and a subtle selected background, so selection does not depend on color alone. Repeat One adds the familiar “1.”
- Center AirPlay below the playback controls in Now Playing. The mini player stays as it is.
- The queue button switches the same modal into a queue view, rather than stacking another modal. Artwork and metadata become a compact current-song row, the upcoming list occupies the middle, and the two views crossfade while playback controls remain fixed. Tapping the queue button again restores the artwork view. Only the queue list scrolls.

## Starting playback

Play starts the album in its original disc/track order. If the current song belongs to the displayed album, the main button reflects Play/Pause and pauses or resumes that song without replacing the queue. Tapping a song starts an album queue from that song onward.

Starting another album or tapping a song in an album replaces the previous playback queue. Adding music without replacing it uses the trailing Add to Queue swipe action.

Previous follows actual listening history. Add to Queue appends after everything already queued.

## Repeat

One button cycles through Off → Repeat All → Repeat One → Off. Its accessibility label announces the current mode.

- Off: stop at the end of the queue.
- Repeat All: replay the full current playback queue, including manually added entries. Preserve queue order each cycle.
- Repeat One: replay the current song when it finishes. Manually pressing Next still advances; Repeat One then applies to that song.

Starting another album preserves the chosen repeat mode. An unavailable file still surfaces the existing error; repeat must not create an endless error/retry loop.

## Building and editing the queue

Swiping left on a song or album row reveals one native trailing action: an icon-only queue-plus button. Tapping it appends the song or entire album after everything already queued. The visible action has no text; VoiceOver announces “Add to Queue.” A swipe reveals the button rather than automatically adding on a full swipe.

There is no Play Next action or long-press queue menu. Moving something nearer the front remains available through reordering in the queue view.

An added album stays in track order at insertion. If nothing is loaded, Add to Queue starts the selected music. If playback is paused, adding music leaves it paused. Intentional duplicate entries are allowed and independently editable.

The queue view has a compact current-song row and a Playing Next list. Upcoming rows show artwork, song title, and artist, with native touch-and-hold dragging and swipe-to-remove, without an Edit mode. Tapping an upcoming entry jumps to it, passing over preceding entries. A Clear action removes upcoming entries while allowing the current song to finish; those removed entries must not return through repeat. An empty upcoming list says “Nothing queued.”

Queue order is the source of truth: Next follows exactly the displayed list. Reordering does not interrupt audio. No saved playlists, automatic recommendations, or separate history screen are proposed.

## Remembering playback

Repeat defaults to Off and retains the user's choice. Save the current queue, song, and position so reopening Oto can restore them paused; never start audio merely because the app launched. Switching music folders clears the old queue. Removed files are reconciled on refresh without leaving broken queue entries.

## Suggested implementation order

1. Establish one playback-order model and add repeat, including lock-screen and headphone controls.
2. Add the trailing Add to Queue swipe action and the editable queue view.
3. Add paused restoration and validate interactions among manual ordering, repeat, refresh, and unavailable files.

The user accepted the overall proposal and refined queue insertion to a single trailing icon-only swipe action that appends to the queue.
