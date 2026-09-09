# Shuffle, repeat, and queue proposal

Status: proposal for review; no feature implementation yet.

## Where the controls live

- Album pages: replace the wide Play button with side-by-side Play and Shuffle buttons. Both follow the album artwork accent and keep native button styling.
- Now Playing: place smaller shuffle and repeat controls on either side of the existing previous/play/next controls, with full-sized touch targets. Active modes use the artwork accent and a subtle selected background, so selection does not depend on color alone. Repeat One adds the familiar “1.”
- Add a queue button at the bottom right of Now Playing, alongside the existing AirPlay area. The mini player stays as it is.
- The queue button switches the same modal into a queue view, rather than stacking another modal. Artwork and metadata become a compact current-song row, the upcoming list occupies the middle, and playback controls stay available. Tapping the queue button again restores the artwork view. Only the queue list scrolls.

## Starting playback and shuffle

Play starts the album in its original disc/track order and turns shuffle off. Shuffle starts the entire album in a randomized order and turns shuffle on. Tapping a song starts an album queue from that song; if shuffle is already on, that song plays first and the other album tracks are randomized after it.

Starting an album or tapping a song in an album replaces the previous playback queue. Adding music without replacing it uses the trailing Add to Queue swipe action.

Switching shuffle on during playback randomizes the upcoming songs without restarting the current song or replaying completed entries. Switching it off restores the remaining queue's original sequence. Previous follows actual listening history, including while shuffled.

Add to Queue appends after everything already queued, even when shuffle is on. A subsequent deliberate shuffle toggle may rearrange those entries along with the rest of the upcoming queue. Album and song lists themselves never change order because of shuffle.

## Repeat

One button cycles through Off → Repeat All → Repeat One → Off. Its accessibility label announces the current mode.

- Off: stop at the end of the queue.
- Repeat All: replay the full current playback queue, including manually added entries. If shuffled, generate a fresh order each cycle and avoid repeating the just-finished song first when alternatives exist.
- Repeat One: replay the current song when it finishes. Manually pressing Next still advances; Repeat One then applies to that song.

Starting another album preserves the chosen repeat mode. An unavailable file still surfaces the existing error; repeat must not create an endless error/retry loop.

## Building and editing the queue

Swiping left on a song or album row reveals one native trailing action: an icon-only queue-plus button. Tapping it appends the song or entire album after everything already queued. The visible action has no text; VoiceOver announces “Add to Queue.” A swipe reveals the button rather than automatically adding on a full swipe.

There is no Play Next action or long-press queue menu. Moving something nearer the front remains available through reordering in the queue view.

An added album stays in track order at insertion, even during shuffled playback. If nothing is loaded, Add to Queue starts the selected music. If playback is paused, adding music leaves it paused. Intentional duplicate entries are allowed and independently editable.

The queue view has a compact current-song row and a Playing Next list. Upcoming rows show artwork, song title, and artist, with drag handles for reordering and swipe-to-remove. Tapping an upcoming entry jumps to it, passing over preceding entries. A Clear action removes upcoming entries while allowing the current song to finish; those removed entries must not return through repeat. An empty upcoming list says “Nothing queued.”

Queue order is the source of truth: Next follows exactly the displayed list. Reordering does not interrupt audio. No saved playlists, automatic recommendations, or separate history screen are proposed.

## Remembering playback

Shuffle and repeat default to Off and retain the user's choice. Save the current queue, song, and position so reopening Oto can restore them paused; never start audio merely because the app launched. Switching music folders clears the old queue. Removed files are reconciled on refresh without leaving broken queue entries.

## Suggested implementation order

1. Establish one playback-order model and add shuffle/repeat, including lock-screen and headphone controls.
2. Add the trailing Add to Queue swipe action and the editable queue view.
3. Add paused restoration and validate interactions among manual ordering, shuffle, repeat, refresh, and unavailable files.

The user accepted the overall proposal and refined queue insertion to a single trailing icon-only swipe action that appends to the queue.
