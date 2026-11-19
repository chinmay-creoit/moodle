<?php
// Tiny helper for the entrypoint/cron scripts (does not bootstrap Moodle).
//
//   php moodle-db-check.php ping        exit 0 if the database accepts connections
//   php moodle-db-check.php installed   exit 0 = Moodle installed (core version recorded)
//                                       exit 1 = empty database, nothing installed yet
//                                       exit 2 = tables exist but install never completed
//   (any other failure to connect => exit 3)

$env = static function (string $name, string $default = ''): string {
    $value = getenv($name);
    return ($value === false || $value === '') ? $default : $value;
};
$quote = static fn (string $v): string => "'" . addcslashes($v, "'\\") . "'";

$conn = @pg_connect(sprintf(
    'host=%s port=%s dbname=%s user=%s password=%s connect_timeout=3',
    $quote($env('MOODLE_DB_HOST', 'db')),
    $quote($env('MOODLE_DB_PORT', '5432')),
    $quote($env('MOODLE_DB_NAME', 'moodle')),
    $quote($env('MOODLE_DB_USER', 'moodle')),
    $quote($env('MOODLE_DB_PASSWORD'))
));
if (!$conn) {
    exit(3);
}

$mode = $argv[1] ?? 'ping';
if ($mode === 'ping') {
    exit(0);
}

$prefix = $env('MOODLE_DB_PREFIX', 'mdl_');

$res = pg_query_params($conn, 'SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema() LIMIT 1', []);
if (!$res || pg_num_rows($res) === 0) {
    exit(1); // No tables at all.
}

$res = pg_query_params(
    $conn,
    'SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = $1',
    [$prefix . 'config']
);
if (!$res || pg_num_rows($res) === 0) {
    exit(2); // Tables present but not Moodle's.
}

$res = @pg_query_params($conn, 'SELECT value FROM ' . pg_escape_identifier($conn, $prefix . 'config') . ' WHERE name = $1', ['version']);
exit(($res && pg_num_rows($res) > 0) ? 0 : 2);
