<?php
declare(strict_types=1);

function fail(int $status, string $message): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $message], JSON_UNESCAPED_SLASHES);
    exit;
}

/**
 * Voice name → model directory mapping.
 * Each key is the value accepted in the POST "voice" field.
 */
const VOICES = [
    'amy'      => '/opt/voices/vits-piper-en_US-amy-low',
    'ljspeech' => '/opt/voices/vits-piper-en_US-ljspeech-medium',
    'ryan'     => '/opt/voices/vits-piper-en_US-ryan-high',
    'joe'      => '/opt/voices/vits-piper-en_US-joe-medium',
];

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

// --- Public endpoints (no rotation check) ---
if ($path === '/health' && $method === 'GET') {
    header('Content-Type: application/json');
    echo '{"status":"ok"}';
    exit;
}
if ($path === '/voices' && $method === 'GET') {
    header('Content-Type: application/json');
    echo json_encode(['voices' => array_keys(VOICES)]);
    exit;
}

// --- Rotating URL: POST /synthesizer/vxyz/{day} ---
// day: 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday
if (!preg_match('#^/synthesizer/vxyz/(\d+)$#', $path, $m)) {
    fail(404, 'Not found');
}
if ($method !== 'POST') {
    header('Allow: POST');
    fail(405, 'Method not allowed');
}

$dayProvided = (int)$m[1];
$today = (int)date('w'); // PHP date('w'): 0=Sun .. 6=Sat (UTC)
if ($dayProvided < 0 || $dayProvided > 6 || $dayProvided !== $today) {
    fail(403, 'Forbidden');
}

// --- Validate request body ---
if (($_SERVER['CONTENT_LENGTH'] ?? 0) > 16384) fail(413, 'Request too large');
$raw = file_get_contents('php://input', false, null, 0, 16385);
if ($raw === false || strlen($raw) > 16384) fail(413, 'Request too large');
$data = json_decode($raw, true);
if (!is_array($data) || !isset($data['text']) || !is_string($data['text'])) fail(400, 'Send JSON with a text string');
$text = trim($data['text']);
if ($text === '' || strlen($text) > 1000) fail(400, 'Text must be 1 to 1000 UTF-8 bytes');
$voice = strtolower(trim($data['voice'] ?? 'amy'));
if (!is_string($voice) || !array_key_exists($voice, VOICES)) {
    fail(400, 'Voice must be one of: ' . implode(', ', array_keys(VOICES)));
}

// --- Synthesize ---
try {
    if (!extension_loaded('vocalizer')) throw new RuntimeException('Vocalizer extension missing');
    $modelDir = getenv('TTS_' . strtoupper($voice) . '_MODEL_DIR') ?: VOICES[$voice];
    $engine = \Vocalizer\Engine::load($modelDir, ['threads' => 1]);
    $result = $engine->speak($text, ['timeout_ms' => 30000]);
    $wav = $result->wav();
    header('Content-Type: audio/wav');
    header('Content-Disposition: attachment; filename="speech.wav"');
    header('Cache-Control: no-store');
    header('Content-Length: ' . strlen($wav));
    echo $wav;
} catch (Throwable $e) {
    error_log('TTS generation failed: ' . $e->getMessage());
    fail(500, 'Speech generation failed');
}
