#!/bin/sh

: "${NPM_URL:?NPM_URL required}"
: "${NPM_EMAIL:?NPM_EMAIL required}"
: "${NPM_PASSWORD:?NPM_PASSWORD required}"
: "${PIHOLE_URL:?PIHOLE_URL required}"
: "${PIHOLE_PASSWORD:?PIHOLE_PASSWORD required}"
: "${TARGET_IP:?TARGET_IP required}"
: "${SYNC_INTERVAL:=60}"
: "${SKIP_TLS_VERIFY:=false}"

CURL_OPTS=""
if [ "$SKIP_TLS_VERIFY" = "true" ]; then
  CURL_OPTS="-k"
fi

NPM_TOKEN=""
PIHOLE_SID=""
SYNCED_FILE="/tmp/synced_domains"
LAST_STATE="/tmp/last_npm_state"
: > "$SYNCED_FILE"
: > "$LAST_STATE"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1"; }

is_synced() { grep -qxF "$1" "$SYNCED_FILE" 2>/dev/null; }
mark_synced() { echo "$1" >> "$SYNCED_FILE"; }

# --- NPM Auth ---
npm_auth() {
  response=$(curl -s $CURL_OPTS -X POST "${NPM_URL}/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{\"identity\":\"${NPM_EMAIL}\",\"secret\":\"${NPM_PASSWORD}\"}" 2>/dev/null)
  NPM_TOKEN=$(echo "$response" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  if [ -z "$NPM_TOKEN" ]; then
    log "ERROR: NPM auth failed. Response: $response"
    return 1
  fi
  log "NPM authenticated"
}

# --- NPM Get Proxy Hosts ---
npm_get_domains() {
  curl -s $CURL_OPTS -X GET "${NPM_URL}/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer ${NPM_TOKEN}" 2>/dev/null \
    | sed 's/\[{/\n{/g' \
    | grep -o '"domain_names":\[[^]]*\]' \
    | sed 's/"domain_names":\[//; s/\]//; s/"//g; s/,/\n/g'
}

# --- Pi-hole Auth ---
pihole_auth() {
  response=$(curl -s $CURL_OPTS "${PIHOLE_URL}/api/auth" \
    -X POST -H "Content-Type: application/json" \
    -d "{\"password\":\"${PIHOLE_PASSWORD}\"}" 2>/dev/null)
  PIHOLE_SID=$(echo "$response" | sed -n 's/.*"sid":"\([^"]*\)".*/\1/p')
  if [ -z "$PIHOLE_SID" ]; then
    log "ERROR: Pi-hole auth failed. Response: $response"
    return 1
  fi
  log "Pi-hole authenticated (SID: $(echo $PIHOLE_SID | cut -c1-8)...)"
}

# --- Pi-hole DNS ---
pihole_add() {
  if is_synced "$1"; then return; fi
  # Remove any existing records for this domain with wrong IP
  pihole_cleanup_domain "$1"
  encoded=$(printf '%s' "${TARGET_IP} $1" | sed 's/ /%20/g')
  response=$(curl -s $CURL_OPTS -w '\n%{http_code}' -X PUT \
    "${PIHOLE_URL}/api/config/dns/hosts/${encoded}?sid=${PIHOLE_SID}" 2>/dev/null)
  status=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [ "$status" = "401" ]; then
    pihole_auth && pihole_add "$1" && return
  fi
  if [ "$status" = "201" ]; then
    log "Added DNS: $1 -> ${TARGET_IP}"
  elif echo "$body" | grep -q "already present"; then
    log "Exists DNS: $1"
  else
    log "WARN: DNS HTTP ${status} for $1: ${body}"
    return
  fi
  mark_synced "$1"
}

pihole_cleanup_domain() {
  # Delete any A records for this domain that don't match TARGET_IP
  hosts=$(curl -s $CURL_OPTS "${PIHOLE_URL}/api/config/dns/hosts?sid=${PIHOLE_SID}" 2>/dev/null)
  echo "$hosts" | grep -o '"[^"]*'"$1"'"' | tr -d '"' | while read -r entry; do
    entry_ip=$(echo "$entry" | sed "s/ $1//")
    if [ "$entry_ip" != "${TARGET_IP}" ]; then
      encoded=$(printf '%s' "$entry" | sed 's/ /%20/g')
      curl -s $CURL_OPTS -o /dev/null -X DELETE \
        "${PIHOLE_URL}/api/config/dns/hosts/${encoded}?sid=${PIHOLE_SID}" 2>/dev/null || true
      log "Removed old DNS: $1 -> $entry_ip"
    fi
  done
}

pihole_remove_stale() {
  current_domains="$1"
  for domain in $(cat "$SYNCED_FILE"); do
    if ! echo "$current_domains" | grep -qxF "$domain"; then
      encoded=$(printf '%s' "${TARGET_IP} $domain" | sed 's/ /%20/g')
      curl -s $CURL_OPTS -o /dev/null -X DELETE \
        "${PIHOLE_URL}/api/config/dns/hosts/${encoded}?sid=${PIHOLE_SID}" 2>/dev/null || true
      log "Removed DNS: $domain"
    fi
  done
  echo "$current_domains" > "$SYNCED_FILE"
}

# --- Sync ---
sync_all() {
  domains=$(npm_get_domains)
  if [ -z "$domains" ]; then
    log "No proxy hosts found in NPM"
    return
  fi

  # Sort for consistent comparison
  sorted=$(echo "$domains" | sort)
  last=$(cat "$LAST_STATE" 2>/dev/null)

  if [ "$sorted" = "$last" ]; then
    return
  fi

  log "NPM changed, syncing Pi-hole..."
  for domain in $domains; do
    pihole_add "$domain"
  done

  pihole_remove_stale "$domains"
  echo "$sorted" > "$LAST_STATE"
}

# --- Main ---
log "Starting npm-pihole-sync"
log "NPM URL: ${NPM_URL}"
log "Pi-hole URL: ${PIHOLE_URL}"
log "Target IP: ${TARGET_IP}"

log "Waiting for NPM..."
until npm_auth; do
  sleep 5
done
pihole_auth || { log "Could not authenticate with Pi-hole. Exiting."; exit 1; }

log "Initial sync..."
sync_all
log "Initial sync done"

while true; do
  sleep "$SYNC_INTERVAL"
  sync_all
done
