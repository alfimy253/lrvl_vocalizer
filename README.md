# Native PHP text-to-speech service for Render

A standalone PHP service that can be called from Laravel. It generates WAV speech locally with the Vocalizer PHP extension and the English Piper `en_US-amy-low` (female) and `en_US-john-medium` (male) models. No external paid TTS API is involved. This is a starter service, not a complete Laravel application, user system, or production-ready commercial platform.

## Deploy to Render
url deployed : https://lrvl-vocalizer.onrender.com/

1. Create a GitHub repository containing these files; push it.
2. In Render, create a **Web Service**, connect the repository, and choose **Docker**. Render injects `PORT`; the entrypoint binds Apache to it. Set health check path to `/health`.
3. In Environment, add `TTS_API_KEY` with a long random secret (at least 32 characters). Generate one locally using `openssl rand -hex 32`. Never commit it to Git. Without it the synthesis endpoint returns 503.
4. Deploy and copy the HTTPS service URL. Test the endpoint using the command below. The model is downloaded at build time, so the build needs internet access.

Render needs to support Linux x86-64/amd64. The supplied Vocalizer binary supports PHP 8.4 NTS and glibc; the Docker image runs a build-time extension-load check. The extension, model and API were tested with PHP 8.4 NTS on Linux x86-64 outside Docker; the Docker image and Render deployment have not yet been tested. The bundled voices are U.S. English Amy (female) and John (male). The API returns WAV only; there is no MP3 encoder. Voices are U.S. English only; other languages require selecting and licensing a different compatible voice model. CPU/RAM and timeout limits must be tested on the chosen Render instance. Free tier may be slow, sleep, or lack sufficient memory.

## Local Docker test

```bash
# On ARM machines use the linux/amd64 emulation flag as shown.
docker build --platform linux/amd64 -t native-php-tts .
docker run --rm --platform linux/amd64 -p 10000:10000 \
  -e TTS_API_KEY="$(openssl rand -hex 32)" native-php-tts
```

For a usable local secret across terminals, instead create one in your shell and pass `-e TTS_API_KEY="$TTS_API_KEY"`. Never use the example value as your real key.

```bash
export TTS_API_KEY="$(openssl rand -hex 32)"
docker run --rm --platform linux/amd64 -p 10000:10000 -e TTS_API_KEY native-php-tts
# In another terminal, set the same TTS_API_KEY first, then:
curl -f http://localhost:10000/health
curl -f -X POST http://localhost:10000/synthesize \
  -H "Authorization: Bearer $TTS_API_KEY" -H 'Content-Type: application/json' \
  -d '{"text":"Hello from native PHP text to speech.","voice":"male"}' --output speech.wav
```

Render test: replace `http://localhost:10000` with your Render HTTPS URL and use the Render secret.

## Troubleshooting: curl always returns 401 Unauthorized

A `401` with `WWW-Authenticate: Bearer` means the endpoint ran but could not match the secret. Work through these in order; each one alone causes a 401.

1. **Apache withheld the header.** Apache does not pass `Authorization` to scripts unless told to, so `$_SERVER['HTTP_AUTHORIZATION']` is empty and every key looks wrong. This service now sets `CGIPassAuth On` in `apache-tts.conf`, copies the header in `public/.htaccess`, and falls back to `getallheaders()` in `public/index.php`. If you run an older copy, redeploy or apply those three changes. Rebuild the image after editing `apache-tts.conf`; it is baked in at build time.
2. **No `TTS_API_KEY` in Render.** With a short or missing key the service returns `503 Service is not configured`, not 401, so check the status code before blaming the key.
3. **A proxy or CDN dropped the header.** Some tunnels and proxies strip `Authorization`. Test the origin URL directly, and confirm with `curl -v` that the request actually sends `Authorization: Bearer ...`.
4. **The key contains characters the shell mangles.** Copy it exactly; avoid trailing spaces and quote it: `-H "Authorization: Bearer $TTS_API_KEY"`.
5. **Quotes pasted literally.** `-H "Authorization: Bearer 'abc'"` sends the quotes. Do not wrap the token in extra quotes.
6. **Wrong scheme or case.** The prefix must be `Bearer`; the check is case-insensitive but a bare token without the prefix is rejected.
7. **Env var edited but not redeployed.** Render only applies environment changes after the service restarts; confirm the new value took effect by changing one character and watching the 401 persist, then redeploy.

Quick check that separates auth from synthesis: a 401 is authentication, a `503` is configuration, a `500` means the key was accepted and speech generation failed. Never commit or print the real key while debugging.

```bash
# Show what is actually sent, without printing the key to the terminal history
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$TTS_SERVICE_URL/synthesize" \
  -H "Authorization: Bearer $TTS_API_KEY" -H 'Content-Type: application/json' \
  -d '{"text":"test"}'
```

## Laravel integration

Set `TTS_SERVICE_URL` and `TTS_API_KEY` in your Laravel environment, and put them in `config/services.php`:

```php
'tts' => [
    'url' => env('TTS_SERVICE_URL'),
    'key' => env('TTS_API_KEY'),
],
```

In a controller or queued job (validate and authorize input before this):

```php
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

$response = Http::withToken(config('services.tts.key'))
    ->timeout(60)
    ->post(rtrim(config('services.tts.url'), '/') . '/synthesize', [
        'text' => $text,
        'voice' => 'male', // 'male' or 'female'; defaults to female
    ]);
$response->throw();
$path = 'speech/' . Str::uuid() . '.wav';
Storage::disk('s3')->put($path, $response->body());
```

Configure the S3 disk and access controls independently; Render's container filesystem is ephemeral. Do not send the secret to the browser. Text is limited to 1,000 UTF-8 bytes per request. Send voice as `male` or `female`; omitted defaults to female. Both voices are U.S. English. For long text split into chunks and process with a queue; protect the Laravel endpoint using authentication, rate limits and quotas.

## Security, licences, and operations

- `/health` only confirms Apache responds; it does not perform inference. Test `/synthesize` after every deploy.
- A shared API key protects synthesis but is not per-user authentication. Add rate limiting, abuse monitoring, billing/quotas and network controls before public or commercial use. Avoid logging customer text and protect audio files.
- Generated audio is returned in memory, not stored in the container. Model files are baked into the image.
- Vocalizer is pinned to commit `002d86b709d29cd56e8f317fd3ee69c8b3895231` and the downloaded extension is SHA-256 checked against a pinned hash. Each model archive is pinned to a SHA-256 observed when downloaded during the audit; this detects later changes but is not an independently authenticated publisher checksum. Verify provenance before production. If overriding MODEL or MALE_MODEL build arguments, also set the corresponding MODEL_SHA256 or MALE_MODEL_SHA256 to the reviewed archive hash and use compatible Vocalizer models.
- Review the Vocalizer extension, embedded dependencies (including eSpeak NG), the Piper voice/model licence, and their commercial/distribution obligations separately. See https://github.com/AkramZerarka/vocalizer and https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models. Voice licence terms can differ by model.
- PHP/Apache processes each hold their own model in memory; worker limits are intentionally small. Requests may queue. Monitor memory and latency; this is not a high-concurrency deployment.

## Audit results

The extension binary SHA-256 matched its pinned hash and its Linux shared-library dependencies were inspected; `libgomp1` is explicitly installed in the Dockerfile. Both model archives were downloaded, hash-pinned, and successfully synthesized with the pinned extension using PHP 8.4 NTS. The PHP endpoint was tested with PHP's development server: health, unauthorized, invalid-input, and valid WAV responses passed. This does not test Apache, image building, or Render itself.

## Selecting voices

POST `/synthesize` with JSON `{"text":"Hello", "voice":"male"}` for John or `{"text":"Hello", "voice":"female"}` for Amy. The default is female. Unknown voice values return HTTP 400. Audio is WAV, not MP3.
