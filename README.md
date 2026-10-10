# coverscene.koplugin

A [KOReader](https://github.com/koreader/koreader) plugin for the sleep screen: instead of showing the cover of the current book on its own, it places the cover into a chosen area of a background picture, e.g. onto the lectern in a picture of a library.

The cover is warped onto four corners you set yourself, so it can follow a slanted surface in perspective and looks like part of the scene.

<img src="example.png" alt="Sleep screen: a book cover standing on the lectern of a library" width="300"> <img src="example_gallery.png" alt="Sleep screen: a book cover hanging framed in a gallery" width="300">

The two bundled pictures with an example cover: the library with its lectern and the gallery with its frame.

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
3. Check the result with **Background pictures → Library (bundled) → Preview**.

Out of the box this alternates between the two bundled pictures, `library.png` and `gallery.png` (both 1236×1648, 3:4 like a Kindle Paperwhite), with the corners already set to the lectern and the frame, so no further setup is needed.

## Background pictures

**Background pictures** lists the pictures, at first **Library (bundled)** and **Gallery (bundled)**. With more than one picture in the list, each sleep screen shows another one.

Tapping a picture in the list gives you **Use this picture**, **Set cover corners**, **Preview** and **Remove** for that picture. Every picture has its own corners.

Unticking **Use this picture** takes a picture out of the rotation but keeps it in the list with its corners, so you can switch it back on later; the list shows a check mark for the pictures in use. With all of them switched off, the sleep screen shows the plain cover.

Removing only takes the picture out of the list; a removed bundled picture can be put back with **Add Library (bundled)** or **Add Gallery (bundled)**.

To use a picture of your own:

1. Copy it anywhere onto the device.
2. Pick it with **Add background picture**. The corner editor opens right away, so you can tell the plugin where the cover goes (see below).

If you only want your own pictures, remove the bundled ones. The file of a removed picture stays where it is.

The background is scaled to fill the screen in portrait and cropped centered, so a picture with the screen's aspect ratio shows completely.

**Order of pictures** chooses between going through the list in turn and picking one at random (never the same twice in a row). A picture whose file is missing, e.g. on a card that is not inserted, is marked "(missing)" and skipped.

**Reset to default** goes back to the two bundled pictures alone, with their original corners. Your picture files are not deleted.

## Setting the corners

**Set cover corners** opens that background picture full screen with the current book's cover (or a checkerboard, if there is none) warped onto the four corners. The screen has to be in portrait.

- `◤ ◥ ◢ ◣` pick the corner to move; it gets the thick marker.
- Tap the picture to put the picked corner there.
- `◁ △ ▽ ▷` move it by the step shown on the **Step** button; tap that button to switch between 1, 5 and 25 px.
- **Move bar** flips the button bar between bottom and top, in case it covers the area you are working on.
- **Save** keeps the corners, **Cancel** discards them.

The cover is stretched to fill the four corners exactly, so the area should have roughly a book's proportions. The corners are stored relative to the picture, not the screen, so they stay correct on a device with a different resolution.

## Structure

- `coverscene_compose.lua`: scales the background and warps the cover onto the four corners.
- `coverscene_editor.lua`: the full-screen corner editor.
- `coverscene_scenes.lua`: the list of background pictures with their corners, and the rotation between them.
- `main.lua` / `_meta.lua`: plugin registration, menu entries and the hook into KOReader's sleep screen.
- `library.png`, `gallery.png`: the bundled background pictures.
- `example.png`, `example_gallery.png`: the pictures shown in this README, not used by the plugin.

## License

[AGPL-3.0](LICENSE), the same license as KOReader.
