# Project: LocalDrop – Build a Fully Functional Offline Media Sharing App

You are a senior Flutter, Rust, networking, and mobile systems engineer.

Your task is to transform the existing LocalDrop Flutter UI project into a fully functional, production-ready local-network photo and video sharing application.

IMPORTANT: The existing Flutter UI and visual design are already implemented. Preserve the existing design, screens, typography, colors, spacing, navigation, and user experience.

Do not redesign the application unless a design change is absolutely necessary for functionality.

Do not create mock implementations, fake progress indicators, simulated uploads, or placeholder functionality.

Every implemented feature must work.

---

# 1. Product Overview

LocalDrop allows a group of people to share photos and videos over a local Wi-Fi network without requiring:

- Internet connectivity.
- Cloud storage.
- User accounts.
- External servers.
- Media compression.
- Third-party file-sharing services.

Example:

Five friends A, B, C, D, and E go on a trip.

1. A creates a sharing session.
2. A manually enables their mobile hotspot.
3. B, C, D, and E connect to A's hotspot.
4. A starts the LocalDrop session.
5. LocalDrop starts a local media-sharing server on A's phone.
6. A displays a QR code.
7. Other participants scan the QR code.
8. Everyone can upload photos and videos.
9. Everyone can browse and download original-quality media.

All transfers must happen over the local network.

---

# 2. Technology Stack

Use the following architecture.

## Mobile application

- Flutter
- Dart
- Material 3
- Android and iOS support

## Native integration

- Kotlin for Android-specific functionality.
- Swift for iOS-specific functionality.
- Flutter platform channels or Pigeon for native communication.

## Backend and transfer engine

- Rust
- Tokio
- Axum
- Tower
- Serde
- SQLite
- SQLx or rusqlite
- SHA-256 for integrity verification.

Use Rust for the local HTTP server, session management, upload processing, file streaming, and media metadata operations.

Flutter should communicate with the Rust engine through a well-defined interface.

Evaluate Rust integration using flutter_rust_bridge or another suitable FFI approach. Choose one approach and use it consistently.

Do not introduce unnecessary dependencies.

---

# 3. Architecture

Implement a host-centric architecture initially.

The host phone acts as the local server and storage device.

Other devices connect through their mobile browsers or the native application.

Architecture:

HOST PHONE
- Flutter application
- Rust local server
- Session manager
- SQLite database
- Local media storage
- HTTP API
- WebSocket server

PARTICIPANTS
- Mobile browser or Flutter application
- Session authentication
- Media gallery
- Upload client
- Download client

All devices must communicate directly over the local Wi-Fi network.

Do not route media through external servers.

---

# 4. Session Creation

Implement a complete session creation workflow.

Requirements:

- Enter session name.
- Enter host display name.
- Generate unique session ID.
- Generate secure random session token.
- Generate four-to-six-digit session PIN.
- Initialize session database.
- Create session media directory.
- Detect available local network interfaces.
- Detect host IP address.
- Start local HTTP server.
- Start WebSocket server.
- Generate QR code containing connection information.
- Display session PIN.
- Display server address.
- Display connected participants.

The host must manually enable their mobile hotspot.

Do not attempt to programmatically enable or control the hotspot.

Provide clear instructions for enabling hotspots on Android and iOS.

The application must detect when the host is not connected to a suitable local network.

Never hardcode an IP address such as 192.168.43.1.

---

# 5. Network Discovery and Connectivity

Implement reliable local-network communication.

Requirements:

- Detect host IP dynamically.
- Detect active network interfaces.
- Determine the appropriate local interface.
- Start server on the correct interface.
- Allow manual IP address entry.
- Support QR-based connection.
- Verify session credentials.
- Detect participant disconnections.
- Handle network changes.
- Handle server startup failures.
- Handle connection timeouts.
- Provide useful diagnostic messages.

Do not assume all hotspot implementations permit communication between connected clients.

Implement connection health checks.

Test Android and iOS compatibility separately.

For initial compatibility, prioritize Android as the host and Android/iOS as participants.

Investigate iOS hosting limitations before claiming full iOS host support.

---

# 6. Session Management API

Implement REST endpoints.

Suggested API:

POST /api/session/join
GET /api/session/info
GET /api/session/participants
POST /api/session/leave
POST /api/session/end

POST /api/media/upload
GET /api/media
GET /api/media/:id
DELETE /api/media/:id

POST /api/media/download
GET /api/media/:id/thumbnail

GET /api/storage/info

GET /api/health

Implement WebSocket events:

- participant_joined
- participant_left
- media_uploaded
- media_deleted
- upload_started
- upload_completed
- upload_failed
- session_ended
- session_updated

Use proper request validation, error handling, authentication, and HTTP status codes.

---

# 7. Media Upload Engine

This is one of the most important components.

Implement:

- Single-file upload.
- Multiple-file upload.
- Large-file streaming.
- Chunked uploads.
- Configurable chunk size.
- Upload progress.
- Upload speed calculation.
- Upload queue.
- Concurrent uploads.
- Pause and resume.
- Retry failed uploads.
- Interrupted upload recovery.
- Duplicate detection.
- SHA-256 integrity verification.
- File type validation.
- File size validation.
- Storage capacity validation.

Do not load entire video files into RAM.

Stream file data directly to disk.

For resumable uploads, maintain upload IDs and chunk metadata.

A partially uploaded file must not appear in the shared gallery until integrity verification succeeds.

Preserve the original uploaded file byte-for-byte.

Never compress, resize, transcode, or modify original media.

---

# 8. Media Gallery

Connect the existing gallery UI to real session data.

Implement:

- Fetch media metadata.
- Display photos.
- Display videos.
- Generate thumbnails.
- Lazy loading.
- Pagination.
- Filter by uploader.
- Filter by media type.
- Sort by upload date.
- Full-screen photo viewer.
- Video playback.
- Display uploader information.
- Display upload timestamp.
- Multi-selection.
- Favorites.
- Real-time gallery updates through WebSocket.

Use efficient thumbnail loading.

Do not load full-resolution images into the gallery grid.

Original files must remain untouched.

---

# 9. Media Download Engine

Implement:

- Download individual photos.
- Download individual videos.
- Download multiple selected files.
- Download original files.
- Download progress.
- Download speed.
- Pause and resume.
- Retry failed downloads.
- Download queue.
- ZIP archive generation.
- Export selected media.

Support Android and iOS media-saving permissions.

Save downloaded media to an appropriate user-accessible location.

Never silently overwrite existing files.

---

# 10. Participant Management

Implement:

- Participant registration.
- Unique participant IDs.
- Display names.
- Participant avatars.
- Online/offline status.
- Participant list.
- Join requests.
- Host approval.
- Remove participant.
- Block participant.
- Reconnect participant.
- Individual upload statistics.

Only authenticated participants should access session media.

---

# 11. Host Dashboard

Connect the existing dashboard to actual data.

Display:

- Connected participants.
- Total photos.
- Total videos.
- Total storage consumed.
- Available device storage.
- Total uploaded data.
- Active uploads.
- Recent activity.
- Session duration.
- Individual participant statistics.

Implement storage warnings and graceful handling of low-storage conditions.

---

# 12. Security

Implement:

- Cryptographically secure session tokens.
- PIN-based authentication.
- Session-scoped authorization.
- Upload authorization.
- Download authorization.
- Participant removal.
- Request validation.
- Path traversal protection.
- File type validation.
- Upload size limits.
- Rate limiting.
- Secure temporary file handling.
- Session cleanup.

Do not expose unrestricted filesystem paths.

Do not trust client-provided filenames.

Use generated internal media IDs.

Since communication happens over a local network, evaluate TLS support and provide clear security boundaries. Do not claim that a session is encrypted unless transport encryption is actually implemented and verified.

---

# 13. Session Lifecycle

Implement:

- Create session.
- Start server.
- Join participants.
- Monitor participants.
- Handle host disconnection.
- Handle application termination.
- Gracefully stop server.
- End session.
- Clean up temporary files.
- Preserve completed media according to host settings.

Do not delete uploaded media unexpectedly.

Ask for confirmation before ending a session or deleting session data.

---

# 14. Flutter UI Integration

Use the existing UI project.

Connect all screens to real application state.

Screens include:

1. Home.
2. Create Session.
3. Starting Session.
4. Host Lobby.
5. Join Session.
6. Join Session Details.
7. Shared Gallery.
8. Media Viewer.
9. Upload Manager.
10. Session Dashboard.
11. Host Controls.
12. Select & Download.

Requirements:

- Preserve the existing design.
- Implement proper state management.
- Implement loading states.
- Implement error states.
- Implement empty states.
- Implement disconnected states.
- Implement success feedback.
- Implement navigation.
- Implement native file selection.
- Implement QR scanning.
- Implement camera permission handling.
- Implement storage permission handling.
- Implement Android and iOS lifecycle handling.

Use a consistent repository/service architecture.

Suggested structure:

lib/
  app/
  core/
  models/
  services/
  repositories/
  providers/
  screens/
  widgets/
  platform/
  utils/

Keep business logic out of UI widgets.

---

# 15. Browser-Based Participant Experience

Participants should not be forced to install LocalDrop.

Implement a responsive web interface served directly by the host's local server.

It must support:

- Session joining.
- Participant name entry.
- PIN authentication.
- Shared gallery.
- Photo preview.
- Video playback.
- File uploads.
- Multiple uploads.
- Upload progress.
- Original-quality downloads.
- Batch downloads.
- Real-time gallery updates.

The browser interface must work on mobile Safari and Chrome.

No external CDN, analytics, fonts, or internet-hosted dependencies should be required for the offline experience.

Bundle the necessary web assets locally.

---

# 16. Performance Requirements

Design for:

- 5–15 participants initially.
- Hundreds or thousands of media files.
- Large 4K videos.
- Concurrent uploads.
- Concurrent downloads.
- Limited mobile RAM.
- Limited host storage.
- Unstable Wi-Fi connections.

Use streaming and bounded concurrency.

Avoid unnecessary file copying.

Avoid blocking the Flutter UI thread.

Make concurrency configurable.

Implement proper cancellation and cleanup.

---

# 17. Testing

Write real tests.

## Rust tests
- Session creation.
- Authentication.
- Upload validation.
- Chunk handling.
- Resume uploads.
- File integrity.
- Duplicate detection.
- Media retrieval.
- Download streaming.
- Participant management.
- Session termination.

## Flutter tests
- Session creation UI.
- Join session UI.
- Gallery rendering.
- Upload state handling.
- Download state handling.
- Error states.
- Navigation.

## Integration tests

Test actual devices:

- Android host + Android client.
- Android host + iPhone client.
- iPhone host + Android client.
- iPhone host + iPhone client.

Test hotspot communication, backgrounding, app termination, reconnection, and large video transfers.

Do not mark a platform as supported until it has been tested on physical devices.

---

# 18. Development Workflow

Work incrementally.

First inspect the entire existing repository.

Understand the current Flutter UI, navigation, dependencies, and project structure.

Do not overwrite existing working code unnecessarily.

Then follow these milestones:

MILESTONE 1:
- Project architecture.
- Rust engine integration.
- Session creation.
- Local HTTP server.
- Host IP detection.

MILESTONE 2:
- QR generation.
- Browser-based joining.
- Participant authentication.
- Participant management.

MILESTONE 3:
- Media upload.
- Streaming.
- Chunked uploads.
- Resumable uploads.
- Integrity verification.

MILESTONE 4:
- Media gallery.
- Thumbnails.
- Photo viewer.
- Video playback.
- Real-time updates.

MILESTONE 5:
- Downloads.
- Batch downloads.
- ZIP exports.
- Transfer management.

MILESTONE 6:
- Host dashboard.
- Security hardening.
- Error handling.
- Performance optimization.

MILESTONE 7:
- Physical device testing.
- Android compatibility.
- iOS compatibility.
- Production build configuration.

After each milestone:
- Run tests.
- Fix compilation errors.
- Update documentation.
- Report implemented features.
- Report remaining limitations.

---

# 19. Non-negotiable Engineering Rules

1. Do not redesign the existing UI.
2. Do not implement fake functionality.
3. Do not use cloud storage.
4. Do not require internet connectivity.
5. Do not compress uploaded media.
6. Do not load large media files entirely into memory.
7. Do not hardcode local IP addresses.
8. Do not assume hotspot clients can always communicate.
9. Do not claim iOS hosting works without physical-device validation.
10. Do not leave critical functionality as TODOs.
11. Do not silently swallow errors.
12. Do not sacrifice existing functionality during refactoring.

Build a modular, maintainable, production-quality application.

Start by inspecting the repository and producing an implementation plan. Then begin Milestone 1 and continue through the milestones without replacing the existing UI with a new design.

The final goal is a working offline media-sharing application where friends can connect to one person's hotspot, join a session, upload original photos and videos, browse the shared gallery, and download each other's media without internet access.