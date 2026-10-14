# rofi-nowplaying

Now-playing controller (MPRIS) as a small rofi dialog: track info, album art, prev/play/next, volume, repeat toggle. Picks the most relevant player (playing > paused > has-title).

Bound to `super+o` in my bspwm setup.

> Based on [Harsh-bin/rofi-music-control](https://github.com/Harsh-bin/rofi-music-control), restyled (translucent, no hardcoded opacity) + cmus fixes (its MPRIS `next` doesn't advance, art comes from the localplayer cache) + dominant-color select button.

## Files
- `nowplaying.sh` — player pick, art fetch (data-uri / file:// / https / cmus cache / fallback), controls
- `nowplaying.rasi` — translucent southeast dialog theme
- `fallback_album_art.png` — used when no art is exposed
- `preview/` — screenshots from upstream

## Deps
`rofi playerctl cmus (optional, for local files) curl libnotify imagemagick metaflac ffmpeg`

## Install
```bash
mkdir -p ~/.config/rofi/nowplaying
cp nowplaying.sh nowplaying.rasi fallback_album_art.png ~/.config/rofi/nowplaying/
chmod +x ~/.config/rofi/nowplaying/nowplaying.sh
```

## sxhkd (super+o)
```
super + o
    pkill -x rofi || ~/.config/rofi/nowplaying/nowplaying.sh
```

`album_art.png` and `song_title.cache` are runtime-generated (gitignored).
