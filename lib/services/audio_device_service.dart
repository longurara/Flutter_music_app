import 'dart:io';

class AudioEndpoint {
  final String name;
  final String status;

  const AudioEndpoint({required this.name, required this.status});
}

class AudioDeviceService {
  const AudioDeviceService();

  Future<List<AudioEndpoint>> listEndpoints() async {
    if (!Platform.isWindows) return const [];
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-PnpDevice -Class AudioEndpoint | Select-Object -Property FriendlyName,Status | Format-Table -HideTableHeaders',
      ]);
      if (result.exitCode != 0) {
        return const [];
      }
      final lines = (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final endpoints = <AudioEndpoint>[];
      for (final line in lines) {
        final parts = line.split(RegExp(r'\s{2,}'));
        if (parts.isEmpty) continue;
        final name = parts.first.trim();
        final status = parts.length > 1 ? parts.last.trim() : 'Unknown';
        endpoints.add(AudioEndpoint(name: name, status: status));
      }
      return endpoints;
    } catch (_) {
      return const [];
    }
  }
}
