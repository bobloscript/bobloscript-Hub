# BobloScript API — v1

Public read API for the BobloScript catalog: scripts, places, and search. Everything the [Hub](https://bobloscript.com/hub) shows is available through it.

## Base URL

```
https://bobloscript.com/v1
```

All responses are JSON. CORS is open, so the API is callable directly from browser JavaScript on any origin.

## Authentication

None required. Every endpoint below is public — no registration, no API key.

Rate limits are applied per client IP.

## Rate limiting

| Bucket | Limit | Applies to |
|---|---|---|
| Search & list | 60 req / 60s | `/search`, `/scripts`, `/scripts/home/:kind`, `/scripts/:idOrSlug`, `/places`, `/places/:slug/scripts` |
| Code | 20 req / 60s | `/scripts/:idOrSlug/code` |
| Events | 10 req / 60s | `/scripts/:idOrSlug/execute`, `/hub/install` |

`GET /v1/health` is not rate limited.

Every response carries:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 59
X-RateLimit-Reset: 1755225600
```

`X-RateLimit-Reset` is a unix timestamp in seconds. On overflow you get `429` with a `Retry-After` header:

```json
{ "code": "RATE_LIMITED", "message": "Too many requests.", "retryAfter": 12 }
```

## Errors

Check the HTTP status code first — error bodies come in two shapes depending on the failure:

```json
{ "code": "RATE_LIMITED", "message": "...", "retryAfter": 12 }
```

```json
{ "statusCode": 404, "message": "Script not found.", "error": "Not Found" }
```

| Status | Meaning |
|---|---|
| 400 | Malformed path, or free-text `q` longer than 100 characters |
| 404 | Script or place not found, or the script is not published |
| 410 | Script existed but has been removed |
| 429 | Rate limit exceeded |
| 502 | Upstream API unreachable |
| 503 | Service temporarily unavailable |

## Pagination

List endpoints share one shape:

```json
{ "page": 1, "limit": 12, "total": 137, "totalPages": 12 }
```

`page` is 1-indexed, clamped to `[1, 100]`. `limit` defaults to 12; the ceiling is 48 on most endpoints and 24 on `/search`.

---

# Endpoints

## `GET /v1/health`

```json
{ "ok": true, "service": "bobloscript-v1" }
```

---

## `GET /v1/search`

Combined script and place search.

| Param | Type | Default | Notes |
|---|---|---|---|
| `q` | string | — | Free text, max 100 characters |
| `type` | `all` \| `scripts` \| `places` | `all` | |
| `page` | int | 1 | `[1, 100]` |
| `limit` | int | 12 | `[1, 24]`, shared across both result sets |

```json
{
  "result": {
    "q": "blox fruits",
    "type": "all",
    "page": 1,
    "limit": 12,
    "scripts": [],
    "places": [],
    "placesTotal": 3,
    "placesTotalPages": 1
  }
}
```

Totals are reported for places only. For paginated script results, use `GET /v1/scripts`.

---

## `GET /v1/scripts`

| Param | Type | Default | Notes |
|---|---|---|---|
| `q` | string | — | Max 100 characters |
| `placeId` | string | — | Roblox place ID |
| `access` | `all` \| `no-key` \| `key-system` | `all` | Aliases accepted: `nokey`, `no key`, `key`, `key system` |
| `page` | int | 1 | `[1, 100]` |
| `limit` | int | 12 | `[1, 48]` |
| `sort` | `newest` \| `oldest` \| `updated` \| `most-views` \| `least-views` \| `trending` | `newest` | |

When `placeId` is set, results are always ordered by last update and `sort` is ignored. In that mode `access` is matched against the raw value, so use `access=NO%20KEY` rather than `access=no-key`.

```json
{
  "result": {
    "page": 1,
    "limit": 12,
    "total": 245,
    "totalPages": 21,
    "scripts": []
  }
}
```

---

## `GET /v1/scripts/home/:kind`

`:kind` is `trending`, `nokey`, or `latest`. Unknown values fall back to `latest`.

Returns up to 12 items, unpaginated.

```json
{ "result": { "scripts": [] } }
```

---

## `GET /v1/scripts/:idOrSlug`

Accepts a UUID or a slug. Returns the full script object.

```json
{
  "script": {
    "id": "b1f2...",
    "slug": "blox-fruits-scripts-2026-no-key",
    "title": "Blox Fruits Scripts 2026 – NO KEY",
    "game": "Blox Fruits",
    "accessType": "NO KEY",
    "highRisk": false,
    "imageUrl": "https://bobloscript.com/uploads/covers/....webp",
    "authorName": "bobloowner",
    "authorProfileSlug": "bobloowner",
    "summary": "No-key Autofarm, ESP, Auto Raids...",
    "tags": ["autofarm", "esp", "no-key"],
    "createdAt": "2026-04-29T00:00:00.000Z",
    "updatedAt": "2026-08-14T00:00:00.000Z",
    "stats": { "views": 18342, "likes": 512 },
    "robloxPlaceId": "2753915549",
    "functions": "Autofarm Level, Fruit Notifier, ESP, Auto Raids, Boss Kill",
    "developer": "Vin",
    "scope": "SINGLE_PLACE"
  }
}
```

`functions` is free text, not an array.

---

## `GET /v1/scripts/:idOrSlug/code`

Returns the script source. Not wrapped in `result`.

```json
{ "id": "b1f2...", "code": "-- ..." }
```

---

## `POST /v1/scripts/:idOrSlug/execute`

Records a run event. No request body. Repeat calls for the same script from the same client within a short window are deduplicated.

```json
{ "ok": true, "counted": true }
```

---

## `POST /v1/hub/install`

Records one Hub install ping. No path parameter, no body.

```json
{ "ok": true }
```

---

## `GET /v1/places`

| Param | Type | Default |
|---|---|---|
| `q` | string | — |
| `page` | int | 1, `[1, 100]` |
| `limit` | int | 12, `[1, 48]` |

Ordered by views.

```json
{
  "result": {
    "page": 1,
    "limit": 12,
    "total": 41,
    "totalPages": 4,
    "places": [
      {
        "id": "a91c...",
        "slug": "blox-fruits",
        "name": "Blox Fruits",
        "placeId": "2753915549",
        "imageUrl": "https://bobloscript.com/uploads/....webp",
        "scriptCount": 58,
        "creatorName": "Gamer Robot Inc"
      }
    ]
  }
}
```

---

## `GET /v1/places/:slug/scripts`

`:slug` accepts the place slug, its Roblox place ID, or its internal UUID.

| Param | Type | Default |
|---|---|---|
| `page` | int | 1, `[1, 100]` |
| `limit` | int | 12, `[1, 48]` |

```json
{
  "result": {
    "place": {
      "id": "a91c...",
      "slug": "blox-fruits",
      "name": "Blox Fruits",
      "placeId": "2753915549",
      "imageUrl": "https://bobloscript.com/....webp",
      "scriptCount": 58
    },
    "page": 1,
    "limit": 12,
    "total": 58,
    "totalPages": 5,
    "scripts": []
  }
}
```

The nested `place` object omits `creatorName`.

---

# Data models

### ScriptCard

Returned by `/search`, `/scripts`, `/scripts/home/:kind`, `/places/:slug/scripts`.

```
id                 string (uuid)
slug               string
title              string
game               string
accessType         "NO KEY" | "KEY SYSTEM" | "PAID"
highRisk           boolean
imageUrl           string (url)
authorName         string
authorProfileSlug  string | null
summary            string
tags               string[]
createdAt          string (ISO 8601)
updatedAt          string (ISO 8601)
stats.views        number
stats.likes        number
```

### ScriptDetail

`ScriptCard` plus:

```
robloxPlaceId      string | null
functions          string (free text)
developer          string
scope              "SINGLE_PLACE" | "UNIVERSAL"
```

### PlaceSummary

```
id                 string (uuid)
slug               string
name               string
placeId            string (Roblox place id)
imageUrl           string (url)
scriptCount        number
creatorName        string
```

---

# Examples

```bash
# Health check
curl https://bobloscript.com/v1/health

# Search everything
curl "https://bobloscript.com/v1/search?q=blox+fruits&type=all&limit=12"

# No-key scripts for a place
curl "https://bobloscript.com/v1/scripts?placeId=2753915549&access=NO%20KEY"

# Trending
curl "https://bobloscript.com/v1/scripts/home/trending"

# Script detail by slug
curl "https://bobloscript.com/v1/scripts/blox-fruits-scripts-2026-no-key"

# Script source
curl "https://bobloscript.com/v1/scripts/blox-fruits-scripts-2026-no-key/code"

# Places
curl "https://bobloscript.com/v1/places?q=fruits"
curl "https://bobloscript.com/v1/places/blox-fruits/scripts?limit=24"
```

---

Questions or something broken? [Discord](https://discord.gg/WZMTeKNEbT) · [support@bobloscript.com](mailto:support@bobloscript.com)
