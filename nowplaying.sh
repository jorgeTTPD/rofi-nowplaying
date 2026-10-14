#!/bin/bash

#####################################
## author @Harsh-bin Github #########
## modified: vol/repeat buttons + estilo translúcido
#####################################

# --- Configuration ---
art_file="$HOME/.config/rofi/nowplaying/album_art.png"
fallback_art_file="$HOME/.config/rofi/nowplaying/fallback_album_art.png"
rofi_theme="$HOME/.config/rofi/nowplaying/nowplaying.rasi"
cache_file="$HOME/.config/rofi/nowplaying/song_title.cache"
lp_cache="${XDG_CACHE_HOME:-$HOME/.cache}/localplayer"
lp_songs="$lp_cache/songs.tsv"
lp_thumbs="$lp_cache/thumbs"
lp_sock="$lp_cache/cmus.sock"
# Cursor según carátula (igual que lyrics/localplayer): fondo del botón
# seleccionado con el tono dominante. Caché compartida (mismos thumbs).
DEFAULT_SELECTED="#89b4fa"
COLORCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/lyrics/colors"

# --- Functions ---

# Ruta sonando en cmus (cmus no publica mpris:artUrl ni xesam:url).
# Socket privado del reproductor local primero, por defecto después.
cmus_current_file() {
    local f
    f=$(timeout 3 cmus-remote --server "$lp_sock" -Q 2>/dev/null | awk '/^file /{sub(/^file /,""); print; exit}')
    [ -n "$f" ] && { printf '%s' "$f"; return 0; }
    f=$(timeout 3 cmus-remote -Q 2>/dev/null | awk '/^file /{sub(/^file /,""); print; exit}')
    [ -n "$f" ] && { printf '%s' "$f"; return 0; }
    return 1
}

# Envía orden a cmus (socket privado, respaldo: por defecto). $1 = args de cmus-remote.
cmus_cmd() {
    timeout 5 cmus-remote --server "$lp_sock" "$@" 2>/dev/null \
        || timeout 5 cmus-remote "$@" 2>/dev/null
}

is_cmus() {
    [[ "$active_player" == "cmus" || "$active_player" == cmus.* ]]
}

# Portada de cmus desde la caché del reproductor local ($1 = path).
cmus_cover_to_art() {
    local p="$1" entry artist album key thumb out
    [ -n "$p" ] || return 1
    if [ -f "$lp_songs" ]; then
        entry=$(awk -F'\t' -v q="$p" '$5 == q {print $2 "\t" $4; exit}' "$lp_songs")
        if [ -n "$entry" ]; then
            artist="${entry%%$'\t'*}"; album="${entry#*$'\t'}"
            if [ -n "$artist" ] && [ -n "$album" ]; then
                key=$(printf '%s|%s' "$artist" "$album" | md5sum | cut -c1-16)
                thumb="$lp_thumbs/$key.jpg"
                if [ -f "$thumb" ]; then
                    cp -f "$thumb" "$art_file" 2>/dev/null && return 0
                fi
            fi
        fi
    fi
    # Respaldo: arte embebido del propio archivo (pistas fuera del índice).
    # Misma clave que cover_thumb() del reproductor (md5 de la ruta).
    key=$(printf '%s' "$p" | md5sum | cut -c1-16)
    out="$lp_thumbs/$key.jpg"
    if [ ! -f "$out" ] && [ ! -f "$out.none" ]; then
        mkdir -p "$lp_thumbs"
        case "$p" in
            *.flac|*.FLAC)
                metaflac --export-picture-to="$out" "$p" >/dev/null 2>&1 ;;
            *.mp3|*.MP3|*.m4a|*.M4A|*.ogg|*.OGG|*.opus|*.OPUS|*.wav|*.WAV)
                ffmpeg -y -v error -i "$p" -an -vcodec copy -frames:v 1 "$out" >/dev/null 2>&1 ;;
        esac
        [ -f "$out" ] || : > "$out.none"
    fi
    [ -f "$out" ] && cp -f "$out" "$art_file" 2>/dev/null
}

# Escape XML special characters for Pango markup
escape_characters() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

dominant_color() { # cover.jpg — imprime #rrggbb vibrante (cacheado) o default
    local cover="$1" key hexfile hex
    [ -n "$cover" ] && [ -f "$cover" ] || { printf '%s' "$DEFAULT_SELECTED"; return 0; }
    # Sin carátula real no hay nada que extraer: conserva el azul del rasi.
    [ "$cover" = "$fallback_art_file" ] && { printf '%s' "$DEFAULT_SELECTED"; return 0; }
    # art_file es copia con nombre fijo: la clave es el contenido.
    key=$(md5sum "$cover" 2>/dev/null | cut -c1-16)
    [ -z "$key" ] && { printf '%s' "$DEFAULT_SELECTED"; return 0; }
    mkdir -p "$COLORCACHE" 2>/dev/null
    hexfile="$COLORCACHE/art-$key.hex"
    if [ -f "$hexfile" ] && [ "$hexfile" -nt "$cover" ]; then
        hex=$(cat "$hexfile" 2>/dev/null)
        case "$hex" in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
            printf '%s' "$hex"; return 0 ;; esac
    fi
    # Histograma de 6 colores: puntúa píxeles × saturación, descarta grises,
    # negros y blancos puros; luego fija luminancia al rango legible [90,200]
    # para que el texto oscuro contraste sobre el seleccionado.
    hex=$(timeout 5 magick "$cover" -resize 80x80! -colors 6 -format "%c" histogram:info:- 2>/dev/null | awk '
        {
            count = $1; sub(/:$/, "", count)
            if (match($0, /\(([0-9.]+),([0-9.]+),([0-9.]+)\)/)) {
                rgb = substr($0, RSTART + 1, RLENGTH - 2)
                n = split(rgb, c, ",")
                r = c[1] + 0; g = c[2] + 0; b = c[3] + 0
                mx = (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b)
                mn = (r < g) ? ((r < b) ? r : b) : ((g < b) ? g : b)
                sat = mx - mn
                if (match($0, /#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/))
                    hx = substr($0, RSTART, 7)
                else
                    next
                score = count * sat
                if (score > best_score && sat >= 25 && mx >= 50 && mx <= 235) {
                    best_score = score; best_hx = hx
                }
                if (count * (1 + sat / 60) > fb_score) {
                    fb_score = count * (1 + sat / 60); fb_hx = hx
                }
            }
        }
        END {
            hx = (best_score > 0) ? best_hx : fb_hx
            if (hx == "") exit 1
            print hx
        }')
    if [ -z "$hex" ]; then
        hex=$(timeout 5 magick "$cover" -resize 1x1 txt:- 2>/dev/null | grep -om1 '#[0-9A-Fa-f]\{6\}')
    fi
    case "$hex" in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
        *) hex="$DEFAULT_SELECTED" ;; esac
    # Normaliza luminancia a [90,200] escalando canales (conserva el tono).
    if [ "$hex" != "$DEFAULT_SELECTED" ]; then
        hex=$(printf '%s' "$hex" | awk '
            {
                hx = $0; sub(/^#/, "", hx)
                r = strtonum("0x" substr(hx, 1, 2)) + 0
                g = strtonum("0x" substr(hx, 3, 2)) + 0
                b = strtonum("0x" substr(hx, 5, 2)) + 0
                lum = (299 * r + 587 * g + 114 * b) / 1000
                if (lum < 90 && lum > 0) {
                    f = 90 / lum
                    r = (r * f > 255) ? 255 : int(r * f)
                    g = (g * f > 255) ? 255 : int(g * f)
                    b = (b * f > 255) ? 255 : int(b * f)
                } else if (lum > 200) {
                    f = 200 / lum
                    r = int(r * f); g = int(g * f); b = int(b * f)
                }
                printf "#%02X%02X%02X", r, g, b
            }')
    fi
    case "$hex" in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
        *) hex="$DEFAULT_SELECTED" ;; esac
    printf '%s' "$hex" > "$hexfile" 2>/dev/null
    printf '%s' "$hex"
}

# Decode URL-encoded paths (file:// album art of browsers)
url_decode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

# Determine active player
players_list=$(playerctl -l 2>/dev/null)
active_player=""
active_player_priority=0

while IFS= read -r player; do
    if [ -z "$player" ]; then continue; fi

    status=$(playerctl -p "$player" status 2>/dev/null | tr '[:upper:]' '[:lower:]')
    title=$(playerctl -p "$player" metadata title 2>/dev/null)

    # Priority Levels:
    # 3 = Playing
    # 2 = Paused
    # 1 = Stopped (but has media/title)
    # 0 = Ghost / No media like chromium based browsers
    current_priority=0

    if [ "$status" == "playing" ]; then
        current_priority=3
    elif [ "$status" == "paused" ]; then
        current_priority=2
    elif [ -n "$title" ]; then
        current_priority=1
    fi

    if [ "$current_priority" -gt "$active_player_priority" ]; then
        active_player="$player"
        active_player_priority=$current_priority
    fi
done <<< "$players_list"

# Clean up art and cache files if no active player
if [[ -z "$active_player" ]]; then
    rm -f "$art_file" "$cache_file" 2>/dev/null
fi

# Fetch Data
song_title="Nothing Playing"
song_artist="Unknown"
player_display_name=""

if [[ -n "$active_player" ]]; then
    # Retrieve metadata
    raw_title=$(playerctl -p "$active_player" metadata title 2>/dev/null)
    raw_artist=$(playerctl -p "$active_player" metadata artist 2>/dev/null)

    # Escape special characters
    clean_name="${active_player%%.*}"
    clean_name="$(tr '[:lower:]' '[:upper:]' <<< ${clean_name:0:1})${clean_name:1}"
    player_display_name=$(escape_characters "$clean_name")
    song_title=$(escape_characters "$raw_title")
    song_artist=$(escape_characters "$raw_artist")

    # Handle album art (cache por título; por ruta en cmus)
    cache_key="$raw_title"
    cmus_path=""
    if is_cmus; then
        cmus_path=$(cmus_current_file) || cmus_path=""
        [ -n "$cmus_path" ] && cache_key="$cmus_path"
    fi
    cached_title=""
    if [[ -f "$cache_file" ]]; then
        cached_title=$(cat "$cache_file")
    fi
    if [[ "$cache_key" != "$cached_title" ]] || [[ ! -f "$art_file" ]]; then
        echo "$cache_key" > "$cache_file"

        album_art_url=$(playerctl -p "$active_player" metadata mpris:artUrl 2>/dev/null)

        if [[ -z "$album_art_url" ]]; then
            # Case 0: No art URL found -> cmus usa la caché local, resto fallback
            if is_cmus \
                && cmus_cover_to_art "$cmus_path"; then
                :
            else
                cp -f "$fallback_art_file" "$art_file" 2>/dev/null
            fi
        elif [[ "$album_art_url" =~ ^data:image ]]; then
            # Case 1: Base64 Data URI
            base64_data=$(echo "$album_art_url" | cut -d',' -f2)
            echo "$base64_data" | base64 -d > "$art_file" 2>/dev/null
        elif [[ "$album_art_url" =~ ^file:// ]]; then
            # Case 2: Standard URL (file://) for browsers
            raw_path="${album_art_url#file://}"
            decoded_path="$(url_decode "$raw_path")"
            cp -f "$decoded_path" "$art_file" 2>/dev/null
        elif [[ "$album_art_url" =~ ^https:// ]]; then
            # Case 3: Web URL
            curl -sf "$album_art_url" --output "$art_file" || cp -f "$fallback_art_file" "$art_file" 2>/dev/null
        fi
    fi
fi

# --- Playback buttons (Nerd Font MDI glyphs via Unicode escapes) ---
icon_prev=$'\U000f04ae'   # md-skip_previous
icon_next=$'\U000f04ad'   # md-skip_next
icon_play=$'\U000f040a'   # md-play
icon_pause=$'\U000f03e4'  # md-pause
icon_vol_down=$'\U000f057f'  # md-volume_low
icon_vol_up=$'\U000f057e'    # md-volume_high
icon_repeat=$'\U000f0456'    # md-repeat

pre="$icon_prev"
next="$icon_next"
toggle="$icon_pause"
vol_down="$icon_vol_down"
vol_up="$icon_vol_up"
repeat_btn="$icon_repeat"

player_status=""
notify_status="Paused"

status=""
if [[ -n "$active_player" ]]; then
    status=$(playerctl -p "$active_player" status 2>/dev/null)
fi
if [[ "$status" == "Playing" ]]; then
    player_status="Playing"
    notify_status="Paused"
elif [[ -n "$active_player" ]]; then
    toggle="$icon_play"
    player_status="${status:-Paused}"
    notify_status="Playing"
else
    toggle="$icon_play"
fi

# Repeat indicator for the header line (keeps play state visible)
loop_status=""
if [[ -n "$active_player" ]]; then
    loop_status=$(playerctl -p "$active_player" loop 2>/dev/null)
fi
if [[ "$loop_status" == "Track" || "$loop_status" == "Playlist" ]]; then
    player_status="${player_status} · Repeat ${loop_status}"
fi

# Print Output
display_text="<span weight='light' size='small' alpha='50%'>${player_display_name}${player_status:+ ${player_status}}</span>\n\n${song_title}\n<span size='small' style='italic' alpha='65%'>${song_artist}</span>"

# Evitar comillas dobles (rompen el -theme-str).
display_text="${display_text//\"/}"

# --- Launch Rofi ---
# Botón bajo el cursor con el tono dominante de la carátula actual
# (propiedad directa: redefinir `* { selected: }` rompe el estilo en rofi).
_sel="$DEFAULT_SELECTED"
if [[ -f "$art_file" ]]; then
    _sel=$(dominant_color "$art_file")
    case "$_sel" in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
        *) _sel="$DEFAULT_SELECTED" ;; esac
fi
selected_option=$(printf '%s\n' "$pre" "$toggle" "$next" "$vol_down" "$vol_up" "$repeat_btn" | rofi -dmenu \
    -theme "$rofi_theme" \
    -theme-str "textbox-custom { str: \"$display_text\"; }" \
    -theme-str "element selected { background-color: ${_sel}FF; }" \
    -select "$toggle")

case "$selected_option" in
    "$pre")
        if [[ -n "$active_player" ]]; then
            if is_cmus; then
                cmus_cmd -r
            else
                playerctl -p "$active_player" previous
            fi
            notify-send "$player_display_name Skipped" "\n<big>$song_title</big>\n$song_artist" --icon="$art_file"
            sleep 0.3
            exec "$0"
        fi
        ;;
    "$toggle")
        if [[ -n "$active_player" ]]; then
            playerctl -p "$active_player" play-pause
            notify-send "$player_display_name $notify_status" "\n<big>$song_title</big>\n$song_artist" --icon="$art_file"
        fi
        ;;
    "$next")
        if [[ -n "$active_player" ]]; then
            # El Next MPRIS de cmus no avanza: va directo por cmus-remote.
            if is_cmus; then
                cmus_cmd -n
            else
                playerctl -p "$active_player" next
            fi
            notify-send "$player_display_name Skipped" "\n<big>$song_title</big>\n$song_artist" --icon="$art_file"
            sleep 0.3
            exec "$0"
        fi
        ;;
    "$vol_down")
        if [[ -n "$active_player" ]]; then
            new_vol=$(playerctl -p "$active_player" volume 0.05- 2>/dev/null)
            if [[ -n "$new_vol" ]]; then
                vol_pct=$(awk -v v="$new_vol" 'BEGIN { printf "%.0f", v * 100 }')
                notify-send "$player_display_name Volume" "${vol_pct}%" --icon="$art_file"
            fi
            exec "$0"
        fi
        ;;
    "$vol_up")
        if [[ -n "$active_player" ]]; then
            new_vol=$(playerctl -p "$active_player" volume 0.05+ 2>/dev/null)
            if [[ -n "$new_vol" ]]; then
                vol_pct=$(awk -v v="$new_vol" 'BEGIN { printf "%.0f", v * 100 }')
                notify-send "$player_display_name Volume" "${vol_pct}%" --icon="$art_file"
            fi
            exec "$0"
        fi
        ;;
    "$repeat_btn")
        if [[ -n "$active_player" ]]; then
            case "$loop_status" in
                None)  new_loop="Track" ;;
                Track) new_loop="Playlist" ;;
                *)     new_loop="None" ;;
            esac
            playerctl -p "$active_player" loop "$new_loop" 2>/dev/null
            notify-send "$player_display_name Repeat" "$new_loop" --icon="$art_file"
        fi
        ;;
esac
