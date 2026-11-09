# Web build and embedding

Run `powershell -ExecutionPolicy Bypass -File web/export.ps1` from the project directory to rebuild `export/index.zip`. The ZIP contains `index.html` at its root and all runtime files, including the optional full-window `embed.html` wrapper. Upload this ZIP as the playable browser build on itch.io.

The Web preset uses a single thread, no PWA/service worker, adaptive canvas sizing, and a canvas that fills its viewport. Community cookie access tolerates blocked storage and malformed cookies. When browser persistence is unavailable, ownership can only last for the current session; existing saved ownership is retained when storage is available.

## An external embed stays on itch.io's loading screen

Confirmed on 9 November 2026: `https://snugglefox.net/games.json` still referenced upload `20389534`, whose embed returned the loading placeholder. The working itch.io page and upload `20389634` returned the playable game. The SnuggleFox website checkout at `../snuggle-fox-website` has the current upload URL and marks Hearthline as responsive so its fullscreen iframe fills the container. Publish that website's changes to correct the live embed. Replacing the game on itch.io can require updating the upload ID in the website's `games.json` again.

“Loading game for the first time...” belongs to itch.io's player, before this game's HTML loading screen. A screenshot of that message alone does not identify a game-code error. Compare the external site's current iframe URL with itch.io's current **Embed game** code after replacing an upload. Inspect the browser console and Network panel on the external site for a failing itch.io request or blocked iframe navigation. The game page URL and external website URL are needed to diagnose that layer.

For this single-threaded build, itch.io's **SharedArrayBuffer support** is unnecessary. If it is enabled, turn it off and test the external embed again. Threaded builds require cross-origin isolation through the containing pages.

## Fill the available height

The game fills the viewport of its own iframe. Space beneath itch.io's logo/fullscreen controls belongs to the containing website. Give that website's game container a real height, and remove any fixed aspect ratio, fixed pixel height, or max-height on its iframe that leaves unused space. For a full-window player, adapt this to the site's existing selectors:

```css
.game-container {
  position: relative;
  width: 100%;
  height: 100dvh;
  min-height: 0;
}
.game-container iframe {
  position: absolute;
  inset: 0;
  display: block;
  width: 100%;
  height: 100%;
  max-height: none;
  border: 0;
}
.game-container:fullscreen {
  width: 100vw;
  height: 100dvh;
}
```

If the container sits below navigation, give it the remaining viewport height using the host's layout. Keep the current itch.io game iframe URL and fullscreen permissions. A cross-origin game cannot resize its parent website's iframe.

References: [itch.io HTML5 uploads and embed settings](https://itch.io/docs/creators/html5), [Godot Web export and thread requirements](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).
