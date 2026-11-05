# How 4 friends share with LocalDrop

Aarav hosts on his phone; Riya and Karan use the app; Meera uses her phone's browser.
Everything travels over Aarav's hotspot — no internet.

```mermaid
sequenceDiagram
    autonumber
    participant A as Aarav (host phone)
    participant R as Riya (app)
    participant K as Karan (app)
    participant M as Meera (browser)
    A->>A: Turn on hotspot · Create Session<br/>(server starts, QR + PIN shown)
    R->>A: Join hotspot · scan QR · name + PIN
    K->>A: Join hotspot · enter address · name + PIN
    M->>A: Join hotspot · scan QR in camera → browser · name + PIN
    A-->>R: participant_joined (live)
    Note over R: Drop to pool: swipe → share, ← skip
    R->>A: Upload originals in chunks (resumable)
    Note over K: Select mode: tap 12 videos · Send to pool
    K->>A: Upload originals in chunks
    M->>A: Upload from browser
    A->>A: Verify SHA-256 · dedupe · add to pool
    A-->>R: media_uploaded (gallery updates live)
    A-->>K: media_uploaded
    A-->>M: media_uploaded
    R->>A: Download selected originals → phone gallery
    K->>A: Download all as ZIP
    Note over A: App can be closed; session keeps running (Android)
    A->>A: End Session (media stays on Aarav's phone)
    A-->>R: session_ended
    A-->>K: session_ended
    A-->>M: session_ended
```
