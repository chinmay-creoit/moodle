#!/bin/bash
# Emulates Moodle's recommended crontab entry `* * * * * php admin/cli/cron.php`.
#
# Moodle expects a NEW cron.php to be started every minute, even if earlier ones are still alive:
# each process keeps polling for ad hoc tasks for ~3 minutes (core\cron keepalive), so a few
# overlap by design, and a long-running task in one process doesn't stall the others.
# Waiting for each process to finish instead would start cron only every ~3 minutes, which
# Moodle flags as "cron should run every 1 min", and one slow task would block everything.
set -u

APP_DIR=/var/www/html
INTERVAL=60
MAX_PROCESSES="${MOODLE_CRON_MAX_PROCESSES:-6}"   # safety net against pile-up if tasks hang

log() { echo "[moodle-cron] $*"; }

# On `docker stop`, stop the running cron.php processes too.
trap 'log "Stopping."; kill $(jobs -p) 2>/dev/null; exit 0' TERM INT

# The web container performs the install/upgrade; don't run cron against a half-installed site.
until php /usr/local/bin/moodle-db-check.php installed; do
    log "Waiting for Moodle to be installed ..."
    sleep 10 & wait $!
done

log "Starting cron: a new cron.php every ${INTERVAL}s (max ${MAX_PROCESSES} concurrent)."
while true; do
    running=$(jobs -rp | wc -l)
    if [ "$running" -lt "$MAX_PROCESSES" ]; then
        runuser -u www-data -- php "$APP_DIR/admin/cli/cron.php" &
    else
        log "Skipping this tick: ${running} cron.php processes still running (limit ${MAX_PROCESSES})."
    fi
    sleep "$INTERVAL" & wait $!
done
