#!/usr/bin/env bash
# Sonde de disponibilité : alerte ntfy après 2 échecs consécutifs,
# notification de rétablissement au retour. L'état est conservé dans state/.
set -uo pipefail

SITES_FILE="${SITES_FILE:-sites.txt}"
STATE_DIR="${STATE_DIR:-state}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:?NTFY_TOPIC manquant}"
RETRY_DELAY="${RETRY_DELAY:-30}"
TIMEOUT="${TIMEOUT:-20}"

mkdir -p "$STATE_DIR"

probe() {
  # Renvoie 0 si le site répond en 2xx/3xx après redirections.
  local url="$1" code
  code=$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" \
         -A 'fxf-uptime/1.0 (+github actions)' "$url" 2>/dev/null) || code="000"
  echo "$code"
  [[ "$code" =~ ^[23][0-9][0-9]$ ]]
}

notify() {
  local title="$1" prio="$2" tags="$3" msg="$4" click="$5"
  curl -sS --max-time 15 \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: $tags" -H "Click: $click" \
    -d "$msg" "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null \
    || echo "::warning::échec d'envoi ntfy pour $title"
}

now=$(date -u '+%Y-%m-%d %H:%M UTC')

while read -r url; do
  [[ -z "$url" || "$url" == \#* ]] && continue
  host=$(echo "$url" | sed -E 's#https?://##; s#/.*##')
  state_file="$STATE_DIR/$host"
  previous=$(cat "$state_file" 2>/dev/null || echo up)

  if code=$(probe "$url"); then
    current=up
  else
    echo "$host : premier échec (HTTP $code), nouvel essai dans ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
    if code=$(probe "$url"); then current=up; else current=down; fi
  fi
  echo "$host : $current (HTTP $code, précédent : $previous)"

  if [[ "$previous" == up && "$current" == down ]]; then
    echo "down $now HTTP $code" > "$state_file"
    notify "$host DOWN" urgent rotating_light \
      "$host ne répond plus (HTTP $code, 2 essais à ${RETRY_DELAY}s d'intervalle). $now" "$url"
  elif [[ "$previous" == down* && "$current" == up ]]; then
    since=$(cut -d' ' -f2-4 "$state_file")
    echo up > "$state_file"
    notify "$host OK" default white_check_mark \
      "$host répond de nouveau (HTTP $code). Indisponible depuis $since. $now" "$url"
  elif [[ ! -f "$state_file" ]]; then
    echo "$current" > "$state_file"
  fi
done < "$SITES_FILE"
