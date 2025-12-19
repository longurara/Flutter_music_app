import 'dart:convert';

import 'package:http/http.dart' as http;

class DriveSharedFile {
  const DriveSharedFile({required this.id, required this.name});
  final String id;
  final String name;
}

class DriveUserFile {
  const DriveUserFile({
    required this.id,
    required this.name,
    required this.mimeType,
  });
  final String id;
  final String name;
  final String mimeType;
}

class DriveListResult {
  const DriveListResult({required this.files, this.nextPageToken});
  final List<DriveUserFile> files;
  final String? nextPageToken;
}

class DeviceCodeResponse {
  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresIn,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int interval;
  final int expiresIn;
}

class DeviceTokenResponse {
  const DeviceTokenResponse({
    required this.accessToken,
    this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
  });

  final String accessToken;
  final String? refreshToken;
  final int expiresIn;
  final String tokenType;
}

class GoogleDriveService {
  const GoogleDriveService({this.clientId});

  /// OAuth client id for desktop app (user must fill this).
  final String? clientId;

  /// Extracts a Google Drive file id from a share link or raw id.
  String? extractFileId(String input) {
    final patterns = [
      RegExp(r'd/([a-zA-Z0-9_-]+)'),
      RegExp(r'id=([a-zA-Z0-9_-]+)'),
      RegExp(r'file/d/([a-zA-Z0-9_-]+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null && match.groupCount >= 1) {
        return match.group(1);
      }
    }
    if (RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(input.trim())) {
      return input.trim();
    }
    return null;
  }

  /// Extracts a folder id from a shared folder link.
  String? extractFolderId(String input) {
    final patterns = [
      RegExp(r'folders/([a-zA-Z0-9_-]+)'),
      RegExp(r'open\\?id=([a-zA-Z0-9_-]+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null && match.groupCount >= 1) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Builds a direct streamable URL for a public/shared file.
  Uri? toDirectUri(String input) {
    final id = extractFileId(input);
    if (id == null) return null;
    return Uri.parse('https://drive.google.com/uc?export=download&id=$id');
  }

  /// API streaming endpoint when the user already has an OAuth access token.
  Uri? toApiUri(String input) {
    final id = extractFileId(input);
    if (id == null) return null;
    return Uri.https('www.googleapis.com', '/drive/v3/files/$id', {
      'alt': 'media',
    });
  }

  /// Builds an authorized media URL embedding the access token.
  Uri authorizedMediaUri(String fileId, String accessToken) {
    return Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&access_token=$accessToken');
  }

  /// Scrapes public folder listing and returns file ids & names (no API key).
  Future<List<DriveSharedFile>> fetchPublicFolderFiles(String input) async {
    final id = extractFolderId(input);
    if (id == null) return const [];
    final url = Uri.parse('https://drive.google.com/embeddedfolderview?id=$id#list');
    final fallback = Uri.parse('https://drive.google.com/drive/folders/$id');
    try {
      final resp = await http.get(
        url,
        headers: const {
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        },
      );
      if (resp.statusCode != 200) {
        final alt = await http.get(fallback);
        if (alt.statusCode != 200) return const [];
        return _parseFolderHtml(alt.body);
      }
      final files = _parseFolderHtml(resp.body);
      if (files.isNotEmpty) return files;
      final alt = await http.get(fallback);
      if (alt.statusCode != 200) return const [];
      return _parseFolderHtml(alt.body);
    } catch (_) {
      return const [];
    }
  }

  List<DriveSharedFile> _parseFolderHtml(String html) {
    final files = <DriveSharedFile>[];
    final primary = RegExp(
      r'/file/d/([a-zA-Z0-9_-]+)[^>]*>([^<]+)<',
      multiLine: true,
    );
    for (final m in primary.allMatches(html)) {
      final fid = m.group(1);
      final name = m.group(2)?.trim();
      if (fid != null && name != null && name.isNotEmpty) {
        files.add(DriveSharedFile(id: fid, name: name));
      }
    }
    if (files.isNotEmpty) return files;
    final dataAttr = RegExp(
      r'data-id="([a-zA-Z0-9_-]+)".*?data-target="doc".*?title="([^"]+)"',
      multiLine: true,
      dotAll: true,
    );
    for (final m in dataAttr.allMatches(html)) {
      final fid = m.group(1);
      final name = m.group(2)?.trim();
      if (fid != null && name != null && name.isNotEmpty) {
        files.add(DriveSharedFile(id: fid, name: name));
      }
    }
    return files;
  }

  /// Lists user's Drive audio files via OAuth access token.
  Future<DriveListResult> fetchUserAudioFiles(
    String accessToken, {
    String? pageToken,
  }) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'q': "mimeType contains 'audio/' and trashed = false",
        'pageSize': '200',
        'fields': 'files(id,name,mimeType),nextPageToken',
        if (pageToken != null) 'pageToken': pageToken,
      },
    );
    final resp = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (resp.statusCode != 200) {
      return const DriveListResult(files: []);
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final items = (data['files'] as List<dynamic>? ?? [])
        .map((e) => DriveUserFile(
              id: e['id'] as String,
              name: e['name'] as String,
              mimeType: e['mimeType'] as String? ?? '',
            ))
        .toList();
    final next = data['nextPageToken'] as String?;
    return DriveListResult(files: items, nextPageToken: next);
  }

  Future<DeviceCodeResponse?> requestDeviceCode({
    required String clientId,
    required List<String> scopes,
  }) async {
    final uri = Uri.parse('https://oauth2.googleapis.com/device/code');
    final resp = await http.post(
      uri,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'scope': scopes.join(' '),
      },
    );
    if (resp.statusCode != 200) {
      // Log body to console for diagnostics.
      // ignore: avoid_print
      print('Drive device code error ${resp.statusCode}: ${resp.body}');
      return null;
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return DeviceCodeResponse(
      deviceCode: data['device_code'] as String,
      userCode: data['user_code'] as String,
      verificationUrl: data['verification_url'] as String,
      interval: (data['interval'] as num?)?.toInt() ?? 5,
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  Future<DeviceTokenResponse?> pollDeviceToken({
    required String clientId,
    required String deviceCode,
  }) async {
    final uri = Uri.parse('https://oauth2.googleapis.com/token');
    final resp = await http.post(
      uri,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
    );
    if (resp.statusCode != 200) {
      // ignore: avoid_print
      print('Drive token poll ${resp.statusCode}: ${resp.body}');
      return null;
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return DeviceTokenResponse(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String?,
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 3600,
      tokenType: data['token_type'] as String? ?? 'Bearer',
    );
  }
}
