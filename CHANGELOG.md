## 0.3.0

* Generate stable media identity and restore playback progress inside the Android player.
* Remove caller-supplied media IDs and start positions from the Dart interface.
* Give the embedded player a configurable 16:9 adaptive aspect ratio by default.

## 0.2.0

* Pin the Android player submodule to `v0.2.0`.
* Add the reusable inline/fullscreen player host and native overlay extension slot while keeping media and engine switching controller-driven.

## 0.1.0

* Initial Android release with Media3/Ijk switching, Compose controls, playback state, fullscreen, PiP, floating return, and network speed reporting.
* Add shared playback progress restoration, explicit start positions, stable media IDs, and persistent HTTP Range content caching for progressive network files.
