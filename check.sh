#!/usr/bin/env bash
# Sonde de disponibilité.
# - Sites publics (sites.txt) : alerte après 2 échecs HTTP consécutifs.
# - Machines internes (heartbeats.txt) : alerte si aucun battement reçu
#   sur le topic ntfy "<NTFY_TOPIC>-hb" depuis HB_MAX_AGE.
# Notification de rétablissement au retour. L'état est conservé dans state/.
set -uo pipefail

SITES_FILE="${SITES_FILE:-sites.txt}"
HEARTBEATS_FILE="${HEARTBEATS_FILE:-heartbeats.txt}"
STATE_DIR="${STATE_DIR:-state}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:?NTFY_TOPIC manquant}"
HB_TOPIC="${HB_TOPIC:-$NTFY_TOPIC-hb}"
HB_MAX_AGE="${HB_MAX_AGE:-15m}"
RETRY_DELAY="${RETRY_DELAY:-30}"
TIMEOUT="${TIMEOUT:-20}"

mkdir -p "$STATE_DIR"
now=$(date -u '+%Y-%m-%d %H:%M UTC')

probe() {
  # Renvoie 0 si le site répond en 2xx/3xx après redirections.
  local url="$1" code
  code=$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" \
         -A 'fxf-uptime/1.0 (+github actions)' "$url" 2>/dev/null) || code="000"
  echo "$code"
  [[ "$code" =~ ^[23][0-9][0-9]$ ]]
}

notify() {
  local title="$1" prio="$2" tags="$3" msg="$4" click="${5:-}"
  local args=(-H "Title: $title" -H "Priority: $prio" -H "Tags: $tags")
  [[ -n "$click" ]] && args+=(-H "Click: $click")
  curl -sS --max-time 15 "${args[@]}" -d "$msg" "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null \
    || echo "::warning::échec d'envoi ntfy pour $title"
}

# transition <nom> <up|down> <détail> <message de panne> [url]
transition() {
  local name="$1" current="$2" detail="$3" down_msg="$4" url="${5:-}"
  local state_file="$STATE_DIR/$name" previous since
  previous=$(cat "$state_file" 2>/dev/null || echo up)
  echo "$name : $current ($detail, précédent : $previous)"

  if [[ "$previous" == up && "$current" == down ]]; then
    echo "down $now $detail" > "$state_file"
    notify "$name DOWN" urgent rotating_light "$down_msg $now" "$url"
  elif [[ "$previous" == down* && "$current" == up ]]; then
    since=$(cut -d' ' -f2-4 "$state_file")
    echo up > "$state_file"
    notify "$name OK" default white_check_mark \
      "$name répond de nouveau ($detail). Indisponible depuis $since. $now" "$url"
  elif [[ ! -f "$state_file" ]]; then
    echo "$current" > "$state_file"
  fi
}

# --- Sites publics ---------------------------------------------------------
if [[ -f "$SITES_FILE" ]]; then
  while read -r url; do
    [[ -z "$url" || "$url" == \#* ]] && continue
    host=$(echo "$url" | sed -E 's#https?://##; s#/.*##')
    if code=$(probe "$url"); then
      current=up
    else
      echo "$host : premier échec (HTTP $code), nouvel essai dans ${RETRY_DELAY}s"
      sleep "$RETRY_DELAY"
      if code=$(probe "$url"); then current=up; else current=down; fi
    fi
    transition "$host" "$current" "HTTP $code" \
      "$host ne répond plus (HTTP $code, 2 essais à ${RETRY_DELAY}s d'intervalle)." "$url"
  done < "$SITES_FILE"
fi

# --- Machines internes (battements de cœur) --------------------------------
if [[ -f "$HEARTBEATS_FILE" ]] && grep -qv '^\s*\(#\|$\)' "$HEARTBEATS_FILE"; then
  if ! beats=$(curl -fsS --max-time "$TIMEOUT" \
        "$NTFY_SERVER/$HB_TOPIC/json?poll=1&since=$HB_MAX_AGE"); then
    # ntfy injoignable : on ne conclut rien pour éviter une fausse alerte.
    echo "::warning::lecture des battements impossible, contrôle des machines ignoré"
  else
    seen=$(echo "$beats" | jq -r 'select(.event=="message") | .message' | sort -u)
    while read -r name; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      if grep -qxF "$name" <<< "$seen"; then current=up; else current=down; fi
      transition "$name" "$current" "battement sur $HB_MAX_AGE" \
        "$name n'a envoyé aucun battement depuis $HB_MAX_AGE (machine éteinte, hors réseau ou cron arrêté)."
    done < "$HEARTBEATS_FILE"
  fi
fi
