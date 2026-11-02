# Security model

* **Transport is plain HTTP on the local network. It is NOT encrypted.** Anyone on the same
  hotspot/Wi-Fi who can capture traffic can see transferred files. The app states this in the
  host lobby and settings. TLS was evaluated: without an internet CA, a self-signed certificate
  would trigger browser warnings for every browser participant, so it is not offered yet.
* Session access requires the PIN (4–6 digits, CSPRNG; default 6). Brute force is limited to
  5 failures per IP and 30 globally per 5 minutes.
* Each participant gets a 256-bit random bearer token; only its SHA-256 is stored. The browser
  token is an `HttpOnly; SameSite=Strict` cookie. Removing/blocking revokes the token immediately;
  blocking also bans the device id.
* Every media/upload/export endpoint requires an approved participant of this session.
  Exports are bound to the participant that created them. Delete: uploader or host only.
* Client filenames are never used on disk: files are stored as `<random-id>.<sniffed-ext>`.
  IDs are validated as 32 hex characters (no path traversal). Display names are sanitized.
* File type is decided by magic bytes (photos/videos allowlist), not the extension or MIME.
  Client thumbnails are decoded and re-encoded. Size limits apply to files, chunks, JSON bodies
  and thumbnails. Per-IP rate limiting covers all requests.
* Web client: strict CSP (`default-src 'none'`, no inline script), `nosniff`, `X-Frame-Options: DENY`,
  `no-referrer`; all assets are bundled (no CDN).
* Temp upload data is removed on cancel, expiry and session end. Media is kept unless the host
  chooses to delete it (with confirmation).
