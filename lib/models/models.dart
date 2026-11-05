// Data models mirroring the engine's JSON API (see docs/API.md).

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
int? _intOrNull(dynamic v) => v == null ? null : _int(v);

class SessionInfo {
  final String id;
  final String name;
  final String hostName;
  final String hostId;
  final int createdAt;
  final bool ended;
  final bool requireApproval;
  final int pinLength;
  final int participantCount;
  final bool encrypted;
  // Only present for authenticated viewers.
  final String? uploadPermission;
  final String? downloadPermission;
  final bool keepMedia;
  final List<String> urls;
  final String? joinUrl;
  final int chunkSize;
  final int maxChunkSize;
  final int maxFileSize;
  // Host only.
  final String? pin;
  final List<NetworkInterfaceInfo> addresses;
  final String? dataDir;

  const SessionInfo({
    required this.id,
    required this.name,
    required this.hostName,
    this.hostId = '',
    this.createdAt = 0,
    this.ended = false,
    this.requireApproval = false,
    this.pinLength = 6,
    this.participantCount = 0,
    this.encrypted = false,
    this.uploadPermission,
    this.downloadPermission,
    this.keepMedia = true,
    this.urls = const [],
    this.joinUrl,
    this.chunkSize = 8 << 20,
    this.maxChunkSize = 64 << 20,
    this.maxFileSize = 0,
    this.pin,
    this.addresses = const [],
    this.dataDir,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        hostName: j['host_name'] as String? ?? '',
        hostId: j['host_id'] as String? ?? '',
        createdAt: _int(j['created_at']),
        ended: j['ended'] == true,
        requireApproval: j['require_approval'] == true,
        pinLength: _int(j['pin_length'] ?? 6),
        participantCount: _int(j['participant_count']),
        encrypted: j['encrypted'] == true,
        uploadPermission: j['upload_permission'] as String?,
        downloadPermission: j['download_permission'] as String?,
        keepMedia: j['keep_media'] != false,
        urls: (j['urls'] as List?)?.cast<String>() ?? const [],
        joinUrl: j['join_url'] as String?,
        chunkSize: _int(j['chunk_size'] ?? (8 << 20)),
        maxChunkSize: _int(j['max_chunk_size'] ?? (64 << 20)),
        maxFileSize: _int(j['max_file_size']),
        pin: j['pin'] as String?,
        addresses: ((j['addresses'] as List?) ?? const [])
            .map((e) => NetworkInterfaceInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
        dataDir: j['data_dir'] as String?,
      );

  bool get uploadsOpen => uploadPermission != 'host_only';
  bool get downloadsOpen => downloadPermission != 'host_only';
}

class NetworkInterfaceInfo {
  final String name;
  final String ip;
  final String kind;
  final bool usable;
  const NetworkInterfaceInfo({required this.name, required this.ip, required this.kind, required this.usable});
  factory NetworkInterfaceInfo.fromJson(Map<String, dynamic> j) => NetworkInterfaceInfo(
        name: j['name'] as String? ?? '',
        ip: j['ip'] as String? ?? '',
        kind: j['kind'] as String? ?? 'other',
        usable: j['usable'] == true,
      );
}

class Participant {
  final String id;
  final String name;
  final String role;
  final String status;
  final int avatarColor;
  final int joinedAt;
  final int lastSeen;
  final bool online;
  final String initials;
  final int photos;
  final int videos;
  final int bytes;

  const Participant({
    required this.id,
    required this.name,
    this.role = 'participant',
    this.status = 'active',
    this.avatarColor = 0xFFEDE8FF,
    this.joinedAt = 0,
    this.lastSeen = 0,
    this.online = false,
    this.initials = '',
    this.photos = 0,
    this.videos = 0,
    this.bytes = 0,
  });

  bool get isHost => role == 'host';
  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  int get items => photos + videos;

  factory Participant.fromJson(Map<String, dynamic> j) => Participant(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        role: j['role'] as String? ?? 'participant',
        status: j['status'] as String? ?? 'active',
        avatarColor: _int(j['avatar_color'] ?? 0xFFEDE8FF),
        joinedAt: _int(j['joined_at']),
        lastSeen: _int(j['last_seen']),
        online: j['online'] == true,
        initials: j['initials'] as String? ?? '',
        photos: _int(j['photos']),
        videos: _int(j['videos']),
        bytes: _int(j['bytes']),
      );
}

class Uploader {
  final String id;
  final String name;
  final String initials;
  final int? avatarColor;
  const Uploader({required this.id, required this.name, this.initials = '', this.avatarColor});
  factory Uploader.fromJson(Map<String, dynamic> j) => Uploader(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Unknown',
        initials: j['initials'] as String? ?? '',
        avatarColor: _intOrNull(j['avatar_color']),
      );
}

class MediaItem {
  final String id;
  final String filename;
  final String mime;
  final String kind;
  final String ext;
  final int size;
  final String sha256;
  final int createdAt;
  final bool hasThumbnail;
  final int? width;
  final int? height;
  final Uploader uploader;
  final bool favorite;

  const MediaItem({
    required this.id,
    required this.filename,
    required this.mime,
    required this.kind,
    required this.ext,
    required this.size,
    required this.sha256,
    required this.createdAt,
    required this.hasThumbnail,
    required this.uploader,
    this.width,
    this.height,
    this.favorite = false,
  });

  bool get isVideo => kind == 'video';

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        filename: j['filename'] as String? ?? 'file',
        mime: j['mime'] as String? ?? '',
        kind: j['kind'] as String? ?? 'photo',
        ext: j['ext'] as String? ?? '',
        size: _int(j['size']),
        sha256: j['sha256'] as String? ?? '',
        createdAt: _int(j['created_at']),
        hasThumbnail: j['has_thumbnail'] == true,
        width: _intOrNull(j['width']),
        height: _intOrNull(j['height']),
        uploader: Uploader.fromJson((j['uploader'] as Map?)?.cast<String, dynamic>() ?? const {}),
        favorite: j['favorite'] == true,
      );

  MediaItem copyWith({bool? favorite, bool? hasThumbnail, int? width, int? height}) => MediaItem(
        id: id,
        filename: filename,
        mime: mime,
        kind: kind,
        ext: ext,
        size: size,
        sha256: sha256,
        createdAt: createdAt,
        hasThumbnail: hasThumbnail ?? this.hasThumbnail,
        width: width ?? this.width,
        height: height ?? this.height,
        uploader: uploader,
        favorite: favorite ?? this.favorite,
      );
}

class MediaPage {
  final List<MediaItem> items;
  final int total;
  final int? nextOffset;
  const MediaPage(this.items, this.total, this.nextOffset);
}

class StorageInfo {
  final int sessionBytes;
  final int mediaBytes;
  final int? freeBytes;
  final int? totalBytes;
  final bool lowStorage;
  const StorageInfo({this.sessionBytes = 0, this.mediaBytes = 0, this.freeBytes, this.totalBytes, this.lowStorage = false});
  factory StorageInfo.fromJson(Map<String, dynamic> j) => StorageInfo(
        sessionBytes: _int(j['session_bytes']),
        mediaBytes: _int(j['media_bytes']),
        freeBytes: _intOrNull(j['free_bytes']),
        totalBytes: _intOrNull(j['total_bytes']),
        lowStorage: j['low_storage'] == true,
      );
}

class ActivityEntry {
  final int ts;
  final String kind;
  final String detail;
  const ActivityEntry(this.ts, this.kind, this.detail);
  factory ActivityEntry.fromJson(Map<String, dynamic> j) =>
      ActivityEntry(_int(j['ts']), j['kind'] as String? ?? '', j['detail'] as String? ?? '');
}

class ActiveUpload {
  final String uploadId;
  final String? participantName;
  final String filename;
  final int size;
  final int received;
  const ActiveUpload(this.uploadId, this.participantName, this.filename, this.size, this.received);
  factory ActiveUpload.fromJson(Map<String, dynamic> j) => ActiveUpload(
        j['upload_id'] as String? ?? '',
        j['participant_name'] as String?,
        j['filename'] as String? ?? '',
        _int(j['size']),
        _int(j['received']),
      );
}

class SessionStats {
  final int photos;
  final int videos;
  final int mediaBytes;
  final int uploadedBytes;
  final int onlineCount;
  final int durationMs;
  final List<Participant> participants;
  final List<ActiveUpload> activeUploads;
  final List<ActivityEntry> recentActivity;
  final StorageInfo storage;

  const SessionStats({
    this.photos = 0,
    this.videos = 0,
    this.mediaBytes = 0,
    this.uploadedBytes = 0,
    this.onlineCount = 0,
    this.durationMs = 0,
    this.participants = const [],
    this.activeUploads = const [],
    this.recentActivity = const [],
    this.storage = const StorageInfo(),
  });

  factory SessionStats.fromJson(Map<String, dynamic> j) => SessionStats(
        photos: _int(j['photos']),
        videos: _int(j['videos']),
        mediaBytes: _int(j['media_bytes']),
        uploadedBytes: _int(j['uploaded_bytes']),
        onlineCount: _int(j['online_count']),
        durationMs: _int(j['duration_ms']),
        participants: ((j['participants'] as List?) ?? const [])
            .map((e) => Participant.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeUploads: ((j['active_uploads'] as List?) ?? const [])
            .map((e) => ActiveUpload.fromJson(e as Map<String, dynamic>))
            .toList(),
        recentActivity: ((j['recent_activity'] as List?) ?? const [])
            .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        storage: StorageInfo.fromJson((j['storage'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

/// Real-time event from the engine's WebSocket.
class ServerEvent {
  final String type;
  final Map<String, dynamic> data;
  final int ts;
  const ServerEvent(this.type, this.data, this.ts);
  factory ServerEvent.fromJson(Map<String, dynamic> j) => ServerEvent(
        j['type'] as String? ?? '',
        (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        _int(j['ts']),
      );
}

/// Returned by the engine when a host session starts.
class HostSession {
  final String sessionId;
  final String sessionName;
  final String hostName;
  final String pin;
  final String hostToken;
  final String hostParticipantId;
  final int port;
  final String localUrl;
  final List<String> urls;
  final String? joinUrl;
  final List<NetworkInterfaceInfo> addresses;
  final bool networkOk;
  final String sessionDir;
  final bool resumed;

  const HostSession({
    required this.sessionId,
    required this.sessionName,
    required this.hostName,
    required this.pin,
    required this.hostToken,
    required this.hostParticipantId,
    required this.port,
    required this.localUrl,
    required this.urls,
    required this.joinUrl,
    required this.addresses,
    required this.networkOk,
    required this.sessionDir,
    required this.resumed,
  });

  factory HostSession.fromJson(Map<String, dynamic> j) => HostSession(
        sessionId: j['session_id'] as String,
        sessionName: j['session_name'] as String? ?? '',
        hostName: j['host_name'] as String? ?? '',
        pin: j['pin'] as String? ?? '',
        hostToken: j['host_token'] as String,
        hostParticipantId: j['host_participant_id'] as String? ?? '',
        port: _int(j['port']),
        localUrl: j['local_url'] as String,
        urls: (j['urls'] as List?)?.cast<String>() ?? const [],
        joinUrl: j['join_url'] as String?,
        addresses: ((j['addresses'] as List?) ?? const [])
            .map((e) => NetworkInterfaceInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
        networkOk: j['network_ok'] == true,
        sessionDir: j['session_dir'] as String? ?? '',
        resumed: j['resumed'] == true,
      );
}

class StoredSession {
  final String id;
  final String name;
  final int createdAt;
  final int? endedAt;
  final int photos;
  final int videos;
  final int bytes;
  const StoredSession(this.id, this.name, this.createdAt, this.endedAt, this.photos, this.videos, this.bytes);
  bool get ended => endedAt != null;
  factory StoredSession.fromJson(Map<String, dynamic> j) => StoredSession(
        j['id'] as String,
        j['name'] as String? ?? '',
        _int(j['created_at']),
        _intOrNull(j['ended_at']),
        _int(j['photos']),
        _int(j['videos']),
        _int(j['bytes']),
      );
}
