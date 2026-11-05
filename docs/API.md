# LocalDrop engine API

Base URL: `http://<host-ip>:<port>` (default port 8080, falls back to the next free port).
Auth: `Authorization: Bearer <token>` (apps) or the `ld_token` HttpOnly cookie (browser).
Errors: `{"error": {"code": "...", "message": "...", ...}}` with a matching HTTP status.

## Session & participants
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/health` | – | liveness, session id |
| GET | `/api/session/info` | optional | public info; more when signed in; PIN for host only |
| POST | `/api/session/join` | – | `{name, pin, device_id?}` → `{token, participant, status}`; 5 wrong PINs / 5 min per IP, 30 globally → 429 |
| GET | `/api/session/me` | any status | own participant (also when pending) |
| GET | `/api/session/participants` | ✓ | host sees pending/removed/blocked too |
| POST | `/api/session/leave` | ✓ | |
| POST | `/api/session/end` | host | `{delete_media?}` – notifies, cleans temp files, stops server |
| PATCH | `/api/session/settings` | host | `name, upload_permission, download_permission (everyone/host_only), require_approval, keep_media` |
| GET | `/api/session/stats` | ✓ | dashboard: totals, per-participant stats, active uploads, activity, storage |
| POST | `/api/participants/{id}/approve\|reject\|remove\|block` | host | remove/block revoke the token immediately; block bans the device id |
| GET | `/api/storage/info` | ✓ | session bytes, free/total, low-storage flag |

## Media
| Method | Path | Notes |
|---|---|---|
| GET | `/api/media?offset&limit&kind=photo\|video&uploader&favorites=true&order=asc\|desc` | paginated |
| GET/DELETE | `/api/media/{id}` | delete: uploader or host |
| GET | `/api/media/{id}/file[?download=1]` | original bytes, `Range`/`If-Range` (resume, video seek), ETag = SHA-256 |
| GET/PUT | `/api/media/{id}/thumbnail` | 480 px JPEG; PUT (uploader) for videos/HEIC, re-encoded server-side |
| POST/DELETE | `/api/media/{id}/favorite` | per participant |
| POST | `/api/media/download` | `{ids}` → `{export_id, url, size}`; GET `url` streams a ZIP (stored) with Content-Length and Range |

## Resumable uploads
1. `POST /api/media/upload` `{filename, size, sha256?}` → `201 {upload_id, received, chunk_size, max_chunk_size}`.
   Returns `{duplicate: true, media}` if the SHA-256 already exists, or the existing upload (`resumed: true`) when the same file is re-declared.
   Validates extension, size limit and free space (`507`).
2. `PUT /api/uploads/{id}?offset=N` raw bytes, `Content-Length` required, optional `X-Chunk-SHA256`.
   Offset must equal `received` (else `409 offset_mismatch` with `received`). Streams to disk; rolled back on failure.
3. `POST /api/uploads/{id}/complete` `{sha256?}` → full-file SHA-256 verified, type sniffed from magic bytes,
   deduplicated, then atomically moved into the gallery (`media_uploaded`). Nothing appears before this.
* `GET /api/uploads/{id}` (status/offset), `DELETE /api/uploads/{id}` (cancel), `GET /api/uploads`.
* Idle uploads expire after `stale_upload_hours` (default 48).

## WebSocket `/api/ws`
JSON frames `{type, data, ts}`: `hello, participant_joined, participant_left, participant_status (online),
participant_removed, join_request (host), join_approved, media_uploaded, media_updated, media_deleted,
upload_started, upload_progress, upload_completed, upload_failed, session_updated, session_ended,
network_changed (host), storage_warning, resync`. Server pings every 15 s; silent clients are dropped after 45 s.
