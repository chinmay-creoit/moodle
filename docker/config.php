<?php
// Moodle configuration for container deployments.
// Every environment-specific value comes from environment variables, so no secrets live in the image.

unset($CFG);
global $CFG;
$CFG = new stdClass();

$env = static function (string $name, ?string $default = null): ?string {
    $value = getenv($name);
    return ($value === false || $value === '') ? $default : $value;
};

// Database (PostgreSQL).
$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = $env('MOODLE_DB_HOST', 'db');
$CFG->dbname    = $env('MOODLE_DB_NAME', 'moodle');
$CFG->dbuser    = $env('MOODLE_DB_USER', 'moodle');
$CFG->dbpass    = $env('MOODLE_DB_PASSWORD', '');
$CFG->prefix    = $env('MOODLE_DB_PREFIX', 'mdl_');
$CFG->dboptions = [
    'dbpersist'        => false,
    'dbsocket'         => false,
    'dbport'           => $env('MOODLE_DB_PORT', '5432'),
    'dbhandlesoptions' => false,
];

// Public URL: must match exactly what users type in the browser (no trailing slash).
$wwwroot = $env('MOODLE_URL');
if ($wwwroot === null) {
    http_response_code(500);
    exit("MOODLE_URL is not set. Set it to the public URL of this site, e.g. https://lms.example.com\n");
}
$CFG->wwwroot = rtrim($wwwroot, '/');

// TLS is terminated by the reverse proxy (Traefik in Dokploy) when the public URL is https.
$CFG->sslproxy = str_starts_with($CFG->wwwroot, 'https://');

$CFG->dataroot = $env('MOODLE_DATAROOT', '/var/www/moodledata');
$CFG->directorypermissions = 02777;
$CFG->admin = 'admin';

// Apache is configured with FallbackResource /r.php (see docker/apache/moodle.conf).
$CFG->routerconfigured = true;

// Code is baked into the image (read-only for Moodle): plugin installs go through the Dockerfile/git.
$CFG->disableupdateautodeploy = true;

// External binaries installed in the image.
$CFG->pathtogs = '/usr/bin/gs';
$CFG->pathtopdftoppm = '/usr/bin/pdftoppm';

unset($env, $wwwroot);

require_once(__DIR__ . '/lib/setup.php'); // Do not edit.
