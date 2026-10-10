# coverscene.koplugin

A [KOReader](https://github.com/koreader/koreader) plugin for the sleep screen: instead of showing the cover of the current book on its own, it places the cover into a chosen area of a background picture, e.g. onto the lectern in a picture of a library.

The cover is warped onto four corners you set yourself, so it can follow a slanted surface in perspective and looks like part of the scene.

<img src="example.png" alt="Sleep screen: a book cover standing on the lectern of a library" width="400">

The bundled library picture with an example cover on its lectern.

## Install

1. Download this repository (**Code → Download ZIP**) or clone it.
2. Make sure the folder is named exactly `coverscene.koplugin` (the ZIP unpacks as `coverscene.koplugin-main`, so rename it).
3. Copy the folder into KOReader's `plugins/` directory on your device:
   - Kindle: `koreader/plugins/`
   - Kobo: `.adds/koreader/plugins/`
   - Android: `koreader/plugins/`
4. Restart KOReader.

## Setup

1. Set **Settings → Screen → Sleep screen → Wallpaper** to **Show book cover on sleep screen**. The plugin only steps in when that mode actually shows a cover, so KOReader's "ignore book cover" options keep working.
2. In **Settings → Screen → Sleep screen → Book cover in background picture**, tick **Place book cover into background picture**.
3. Check the result with **Preview**.

Out of the box this uses the bundled `library.png` (a library with a lectern, 1236×1648, 3:4 like a Kindle Paperwhite) with the corners already set to its lectern, so no further setup is needed.

## Using your own picture

1. Copy the picture anywhere onto the device.
2. Pick it with **Choose background picture**.
3. Tell the plugin where the cover goes with **Set cover corners** (see below).

The background is scaled to fill the screen in portrait and cropped centered, so a picture with the screen's aspect ratio shows completely.

**Reset to default** goes back to the bundled library picture and its corners. Your own picture file is not deleted.

## Setting the corners

**Set cover corners** opens the background picture full screen with the current book's cover (or a checkerboard, if there is none) warped onto the four corners. The screen has to be in portrait.

- `◤ ◥ ◢ ◣` pick the corner to move; it gets the thick marker.
- Tap the picture to put the picked corner there.
- `◁ △ ▽ ▷` move it by the step shown on the **Step** button; tap that button to switch between 1, 5 and 25 px.
- **Move bar** flips the button bar between bottom and top, in case it covers the area you are working on.
- **Save** keeps the corners, **Cancel** discards them.

The cover is stretched to fill the four corners exactly, so the area should have roughly a book's proportions. The corners are stored relative to the picture, not the screen, so they stay correct on a device with a different resolution.

## Structure

- `coverscene_compose.lua`: scales the background and warps the cover onto the four corners.
- `coverscene_editor.lua`: the full-screen corner editor.
- `main.lua` / `_meta.lua`: plugin registration, menu entries and the hook into KOReader's sleep screen.
- `library.png`: the default background picture.
- `example.png`: the picture shown in this README, not used by the plugin.

## License

[AGPL-3.0](LICENSE), the same license as KOReader.
