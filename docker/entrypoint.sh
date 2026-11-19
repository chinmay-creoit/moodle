#!/bin/bash
# Container entrypoint. For the web server it makes sure moodledata is usable, waits for the
# database, then installs Moodle (first boot) or runs the upgrade (new image version), and
# finally starts Apache. Any other command is executed as-is.
set -euo pipefail

APP_DIR=/var/www/html
DATAROOT="${MOODLE_DATAROOT:-/var/www/moodledata}"

log() { echo "[moodle-entrypoint] $*"; }
as_www() { runuser -u www-data -- "$@"; }

wait_for_db() {
    log "Waiting for database at ${MOODLE_DB_HOST:-db}:${MOODLE_DB_PORT:-5432} ..."
    for _ in $(seq 1 60); do
        if php /usr/local/bin/moodle-db-check.php ping; then
            log "Database is reachable."
            return 0
        fi
        sleep 2
    done
    log "ERROR: database did not become reachable in time."
    return 1
}

install_or_upgrade() {
    local state=0
    php /usr/local/bin/moodle-db-check.php installed || state=$?

    case "$state" in
        0)
            if [ "${MOODLE_AUTO_UPGRADE:-true}" = "true" ]; then
                log "Moodle is installed; running upgrade check (set MOODLE_AUTO_UPGRADE=false to skip)."
                as_www php "$APP_DIR/admin/cli/upgrade.php" --non-interactive
            else
                log "Moodle is installed; MOODLE_AUTO_UPGRADE=false so the upgrade step is skipped."
            fi
            ;;
        1)
            : "${MOODLE_ADMIN_PASSWORD:?MOODLE_ADMIN_PASSWORD must be set for the first install}"
            log "Empty database: installing Moodle (this takes a few minutes) ..."
            as_www php "$APP_DIR/admin/cli/install_database.php" \
                --lang="${MOODLE_LANG:-en}" \
                --adminuser="${MOODLE_ADMIN_USER:-admin}" \
                --adminpass="$MOODLE_ADMIN_PASSWORD" \
                --adminemail="${MOODLE_ADMIN_EMAIL:-admin@example.com}" \
                --fullname="${MOODLE_SITE_FULLNAME:-Moodle}" \
                --shortname="${MOODLE_SITE_SHORTNAME:-Moodle}" \
                --supportemail="${MOODLE_ADMIN_EMAIL:-admin@example.com}" \
                --agree-license
            log "Installation finished. Log in at ${MOODLE_URL:-?} as '${MOODLE_ADMIN_USER:-admin}'."
            ;;
        2)
            log "ERROR: the database contains tables but Moodle's install never completed."
            log "Drop the database (or remove the pgdata volume) and start again to reinstall."
            exit 1
            ;;
        *)
            log "ERROR: could not query the database (exit code $state)."
            exit 1
            ;;
    esac
}

if [ "${1:-}" = "apache2-foreground" ]; then
    # A fresh named volume is owned by root; Moodle runs as www-data.
    mkdir -p "$DATAROOT"
    chown www-data:www-data "$DATAROOT"

    wait_for_db
    install_or_upgrade
fi

exec "$@"
