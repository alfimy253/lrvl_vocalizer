<?php
declare(strict_types=1);

function fail(int $status, string $message): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $message], JSON_UNESCAPED_SLASHES);
    exit;
}

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($path === '/health' && $method === 'GET') {
    header('Content-Type: application/json');
    echo '{"status":"ok"}';
    exit;
}
if ($path !== '/synthesize') fail(404, 'Not found');
if ($method !== 'POST') { header('Allow: POST'); fail(405, 'Method not allowed'); }

if (($_SERVER['CONTENT_LENGTH'] ?? 0) > 16384) fail(413, 'Request too large');
$raw = file_get_contents('php://input', false, null, 0, 16385);
if ($raw === false || strlen($raw) > 16384) fail(413, 'Request too large');
$data = json_decode($raw, true);
if (!is_array($data) || !isset($data['text']) || !is_string($data['text'])) fail(400, 'Send JSON with a text string');
$text = trim($data['text']);
if ($text === '' || strlen($text) > 1000) fail(400, 'Text must be 1 to 1000 UTF-8 bytes');
$voice = $data['voice'] ?? 'female';
if (!is_string($voice) || !in_array($voice, ['female', 'male'], true)) fail(400, 'Voice must be female or male');

try {
    if (!extension_loaded('vocalizer')) throw new RuntimeException('Vocalizer extension missing');
    $model = $voice === 'male'
        ? (getenv('TTS_MALE_MODEL_DIR') ?: '/opt/voices/vits-piper-en_US-john-medium')
        : (getenv('TTS_MODEL_DIR') ?: '/opt/voices/vits-piper-en_US-amy-low');
    $engine = \Vocalizer\Engine::load($model, ['threads' => 1]);
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
