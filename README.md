# Native PHP text-to-speech service for Render

A standalone PHP service that can be called from Laravel. It generates WAV speech locally with the Vocalizer PHP extension and four English Piper voice models. No external paid TTS API is involved. This is a starter service, not a complete Laravel application, user system, or production-ready commercial platform.

## Available voices

| Voice name | Gender | Model | Quality | Character |
|---|---|---|---|---|
| `amy` | Female | en_US-amy | Low | Soft, gentle female |
| `ljspeech` | Female | en_US-ljspeech | Medium | Clear, natural female (studio corpus) |
| `ryan` | Male | en_US-ryan | **High** | Warm, natural male — best male voice |
| `joe` | Male | en_US-joe | Medium | Clear, professional male |

All voices are **U.S. English**. Audio output is WAV only (no MP3).

---

## Deployment notes (Render)

**Deployed URL:** https://lrvl-vocalizer.onrender.com/

### Prerequisites
- **Platform:** Render (Docker environment) or any Docker host running Linux x86-64/amd64
- **PHP:** 8.4 NTS (bundled in Docker image)
- **Architecture:** x86-64 only — the Vocalizer binary does not support ARM/Apple Silicon
- **Memory:** Each voice model loads into memory per Apache worker. Free tier may be tight — test with all 4 voices before going live.
- **Build time:** Docker build downloads ~265 MB of voice models + the Vocalizer extension. Ensure the build environment has internet access.

### Step-by-step deploy
1. Push this repository to GitHub.
2. In Render, create a **Web Service** → connect the repo → choose **Docker** as the environment.
3. Render injects `PORT` automatically; the entrypoint script binds Apache to it.
4. Set health check path to `/health`.
5. **No environment variables required** — the rotating URL pattern replaces API key auth.
6. Deploy. First build takes a few minutes to download models.

### Important notes
- **Free tier:** Render free services spin down after 15 min of inactivity. The first request after idle can take 30–60 seconds and may timeout. Hit `/health` first to wake the service, wait for 200, then call the synthesize endpoint.
- **Timezone:** The rotating URL day number is based on **server time (UTC)**. If your Laravel app is in a different timezone, compute the day number in UTC, not local time.
- **Concurrency:** Apache is configured for 2 workers max (to keep memory low). Requests may queue under load.
- **Ephemeral storage:** Render containers have no persistent disk. Audio is returned directly in the HTTP response — nothing is saved to disk.
- **Redeploy:** After code changes, Render auto-deploys from the connected branch. Manual deploy: Dashboard → your service → **Manual Deploy → Deploy latest commit**.

---

## Rotating URL authentication

Instead of an API key, the synthesize endpoint uses a **rotating day-of-week number** embedded in the URL path. The URL changes daily — if you don't know today's number, you can't call the endpoint.

### URL pattern

```
POST /synthesizer/vxyz/{day_number}
```

| Day | Number | Example URL |
|---|---|---|
| Sunday | `0` | `/synthesizer/vxyz/0` |
| Monday | `1` | `/synthesizer/vxyz/1` |
| Tuesday | `2` | `/synthesizer/vxyz/2` |
| Wednesday | `3` | `/synthesizer/vxyz/3` |
| Thursday | `4` | `/synthesizer/vxyz/4` |
| Friday | `5` | `/synthesizer/vxyz/5` |
| Saturday | `6` | `/synthesizer/vxyz/6` |

- Day number is based on **UTC** (server time).
- Wrong day number → **403 Forbidden**.
- No API key header needed.

---

## API reference

### `GET /health`
Health check. Returns `{"status":"ok"}`. No rotation check.

### `GET /voices`
Lists available voice names. Returns `{"voices":["amy","ljspeech","ryan","joe"]}`. No rotation check.

### `POST /synthesizer/vxyz/{day}`
Generate speech from text. Returns a WAV audio file. Requires correct day number.

**Request body (JSON):**

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `text` | string | ✅ Yes | — | The text to speak. 1–1000 UTF-8 bytes. |
| `voice` | string | No | `"amy"` | Voice name: `amy`, `ljspeech`, `ryan`, or `joe`. |

**Response:** `audio/wav` binary (WAV file).

**Error responses:**

| HTTP Code | Meaning |
|---|---|
| 400 | Invalid text, unknown voice name, or malformed JSON |
| 403 | Wrong day number in URL |
| 404 | Wrong URL path |
| 405 | Wrong HTTP method (must be POST) |
| 413 | Request body too large (>16 KB) |
| 500 | TTS engine failure |

---

## Example curl commands

```bash
# Get today's day number (UTC): date -u +%w  (Linux/macOS)
# Or just use the right number for today.

# Wednesday example (day=3) — Ryan voice (best male)
curl -X POST https://lrvl-vocalizer.onrender.com/synthesizer/vxyz/3 \
  -H "Content-Type: application/json" \
  --data '{"text":"Hello, this is Ryan speaking.","voice":"ryan"}' \
  --output ryan.wav

# Female — Amy (default, omit voice)
curl -X POST https://lrvl-vocalizer.onrender.com/synthesizer/vxyz/3 \
  -H "Content-Type: application/json" \
  --data '{"text":"Hello from Amy."}' \
  --output amy.wav

# Female — LJSpeech
curl -X POST https://lrvl-vocalizer.onrender.com/synthesizer/vxyz/3 \
  -H "Content-Type: application/json" \
  --data '{"text":"Hello from LJSpeech.","voice":"ljspeech"}' \
  --output ljspeech.wav

# Male — Joe
curl -X POST https://lrvl-vocalizer.onrender.com/synthesizer/vxyz/3 \
  -H "Content-Type: application/json" \
  --data '{"text":"Hello from Joe.","voice":"joe"}' \
  --output joe.wav

# List available voices (no day number needed)
curl https://lrvl-vocalizer.onrender.com/voices
```

### Dynamic day number in bash
```bash
# Automatically use today's day number (UTC)
DAY=$(date -u +%w)
curl -X POST "https://lrvl-vocalizer.onrender.com/synthesizer/vxyz/${DAY}" \
  -H "Content-Type: application/json" \
  --data '{"text":"Hello world","voice":"ryan"}' \
  --output speech.wav
```

---

## POST JSON body examples

```json
// Minimal — defaults to amy
{"text": "Hello world"}

// With voice
{"text": "Hello world", "voice": "ryan"}

// All valid voice values:
{"text": "Test", "voice": "amy"}
{"text": "Test", "voice": "ljspeech"}
{"text": "Test", "voice": "ryan"}
{"text": "Test", "voice": "joe"}
```

---

## Laravel integration

Set `TTS_SERVICE_URL` in your Laravel `.env`:

```env
TTS_SERVICE_URL=https://lrvl-vocalizer.onrender.com
```

In `config/services.php`:

```php
'tts' => [
    'url' => env('TTS_SERVICE_URL'),
],
```

In a controller or queued job:

```php
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Carbon\Carbon;

// Get today's day number in UTC (0=Sun, 1=Mon, ..., 6=Sat)
$day = Carbon::now('UTC')->dayOfWeek; // Carbon::SUNDAY = 0

$response = Http::timeout(60)
    ->post(rtrim(config('services.tts.url'), '/') . "/synthesizer/vxyz/{$day}", [
        'text'  => $text,
        'voice' => 'ryan', // 'amy', 'ljspeech', 'ryan', or 'joe'
    ]);
$response->throw();
$path = 'speech/' . Str::uuid() . '.wav';
Storage::disk('s3')->put($path, $response->body());
```

Text is limited to 1,000 UTF-8 bytes per request. Send voice as `amy`, `ljspeech`, `ryan`, or `joe`; omitted defaults to `amy`. All voices are U.S. English. For long text split into chunks and process with a queue; protect the Laravel endpoint using authentication, rate limits and quotas.

---

## Local Docker test

```bash
# On ARM machines use the linux/amd64 emulation flag as shown.
docker build --platform linux/amd64 -t native-php-tts .
docker run --rm --platform linux/amd64 -p 10000:10000 native-php-tts
```

```bash
# Test (use today's day number — Sunday=0, Monday=1, etc.)
DAY=$(date -u +%w)

curl -f http://localhost:10000/health

curl -f -X POST "http://localhost:10000/synthesizer/vxyz/${DAY}" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hello from Amy.","voice":"amy"}' --output amy.wav

curl -f -X POST "http://localhost:10000/synthesizer/vxyz/${DAY}" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hello from Ryan.","voice":"ryan"}' --output ryan.wav

curl -f -X POST "http://localhost:10000/synthesizer/vxyz/${DAY}" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hello from Joe.","voice":"joe"}' --output joe.wav

curl -f -X POST "http://localhost:10000/synthesizer/vxyz/${DAY}" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Hello from LJSpeech.","voice":"ljspeech"}' --output ljspeech.wav
```

Render test: replace `http://localhost:10000` with your Render HTTPS URL.

---

## Security and operations

- `/health` and `/voices` are open (no rotation check) for monitoring and service discovery.
- The rotating URL pattern provides lightweight obscurity, not strong security. Add rate limiting, IP allowlists, or an API gateway for production use.
- Generated audio is returned in memory, not stored in the container. Model files are baked into the image.
- Vocalizer is pinned to commit `002d86b709d29cd56e8f317fd3ee69c8b3895231` with a SHA-256 pinned extension hash. The Amy model archive is also hash-pinned. Other models are downloaded without pinning — pin their SHA-256 after first successful build for tamper detection.
- Review the Vocalizer extension, embedded dependencies (including eSpeak NG), the Piper voice/model licence, and their commercial/distribution obligations separately. See https://github.com/AkramZerarka/vocalizer and https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models.
- PHP/Apache processes each hold their own model in memory; worker limits are intentionally small (2 max). Requests may queue. Monitor memory and latency.
