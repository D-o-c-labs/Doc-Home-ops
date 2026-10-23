#!/bin/sh
# Two-way sync of the Home Assistant config with GitHub.
# Every interval: commit local (UI) edits, rebase them onto the remote branch,
# push, and reload Home Assistant when pulled changes pass the config check.
# On a rebase conflict nothing is overwritten: local commits stay, the sync
# retries each interval and a persistent notification is raised once.
set -u

REPO_DIR=${REPO_DIR:-/config}
BRANCH=${GIT_BRANCH:-master}
REMOTE_URL=${GIT_REMOTE_URL:?GIT_REMOTE_URL is required}
INTERVAL=${SYNC_INTERVAL:-300}
# Not localhost: busybox wget only tries ::1 and Home Assistant listens on IPv4.
HASS_URL=${HASS_URL:-http://127.0.0.1:8123}

export HOME=/tmp
install -m 600 /secrets/ssh/id_ed25519 /tmp/id_ed25519
export GIT_SSH_COMMAND="ssh -i /tmp/id_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/git-sync/known_hosts"

log() { echo "$(date -u +%FT%TZ) $*"; }
git() { command git -C "$REPO_DIR" -c safe.directory="$REPO_DIR" "$@"; }

hass_post() {
    data=${2-}
    [ -n "$data" ] || data='{}'
    wget -q -O - --header "Authorization: Bearer $HASS_TOKEN" \
        --header "Content-Type: application/json" --post-data "$data" "$HASS_URL/api/$1"
}

notify() {
    hass_post services/persistent_notification/create \
        "{\"notification_id\":\"git_sync\",\"title\":\"Config sync\",\"message\":\"$1\"}" >/dev/null ||
        log "could not raise notification"
}

# Clears reload_pending once the pulled config was reloaded or rejected; an
# unreachable API (e.g. Home Assistant still starting) keeps it for the next run.
reload() {
    if ! result=$(hass_post config/core/check_config); then
        log "config check request failed; retrying next run"
        return
    fi
    case "$result" in
    *'"result":"valid"'* | *'"result": "valid"'*)
        if hass_post services/homeassistant/reload_all >/dev/null; then
            log "reloaded Home Assistant"
            reload_pending=""
        else
            log "reload request failed; retrying next run"
        fi
        ;;
    *)
        log "config check failed, not reloading: $result"
        notify "Pulled config failed the check and was not reloaded. See the git-sync container logs."
        reload_pending=""
        ;;
    esac
}

last_conflict=""
reload_pending=""

sync_once() {
    git add -A
    if ! git diff --cached --quiet; then
        git commit -q -m "chore: sync changes from Home Assistant" && log "committed local changes"
    fi

    git fetch -q "$REMOTE_URL" "$BRANCH" || { log "fetch failed"; return; }
    remote=$(git rev-parse FETCH_HEAD)
    before=$(git rev-parse HEAD)

    if ! git merge-base --is-ancestor "$remote" HEAD; then
        # Check for conflicts in memory first so /config never holds conflict markers.
        if ! git merge-tree --write-tree HEAD "$remote" >/dev/null 2>&1 ||
            ! git rebase -q "$remote" >/dev/null 2>&1; then
            git rebase --abort 2>/dev/null
            log "rebase onto $BRANCH ($remote) conflicts; keeping local commits"
            if [ "$remote" != "$last_conflict" ]; then
                notify "Local config changes conflict with GitHub $BRANCH. Sync is paused until the conflict is resolved."
                last_conflict=$remote
            fi
            return
        fi
        last_conflict=""
    fi

    if ! git merge-base --is-ancestor HEAD "$remote"; then
        git push -q "$REMOTE_URL" "HEAD:$BRANCH" && log "pushed $(git rev-parse --short HEAD)"
    fi

    if [ -n "$(git diff --name-only "$before" HEAD)" ]; then
        log "pulled $(git rev-parse --short "$before")..$(git rev-parse --short HEAD)"
        reload_pending=1
    fi
}

trap 'exit 0' TERM INT
log "syncing $REPO_DIR with $BRANCH every ${INTERVAL}s"
while true; do
    sync_once
    [ -z "$reload_pending" ] || reload
    sleep "$INTERVAL" &
    wait $!
done
