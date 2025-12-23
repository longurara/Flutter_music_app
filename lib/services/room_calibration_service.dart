import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';

class RoomCalibrationResult {
  final Map<int, double> bandDb;
  final Map<int, double> suggestedGains;
  final double rmsDb;
  final bool success;
  final String? error;

  const RoomCalibrationResult({
    required this.bandDb,
    required this.suggestedGains,
    required this.rmsDb,
    required this.success,
    this.error,
  });

  factory RoomCalibrationResult.failure(String message) {
    return RoomCalibrationResult(
      bandDb: const {},
      suggestedGains: const {},
      rmsDb: -120,
      success: false,
      error: message,
    );
  }
}

class RoomCalibrationService {
  const RoomCalibrationService({
    this.sampleRate = 44100,
    this.captureSeconds = 3,
    this.maxCorrectionDb = 8.0,
    this.preferredDeviceId,
  });

  final int sampleRate;
  final int captureSeconds;
  final double maxCorrectionDb;
  final String? preferredDeviceId;

  static const List<int> _bands = [60, 230, 910, 3600, 14000];

  Future<RoomCalibrationResult> measure() async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      return RoomCalibrationResult.failure('Microphone permission denied.');
    }
    final inputDevice = await _pickDevice(recorder);
    Stream<Uint8List> micStream;
    var started = false;
    try {
      micStream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          device: inputDevice,
        ),
      );
      started = true;
      final bytes = <int>[];
      final completer = Completer<void>();
      late final StreamSubscription<Uint8List> sub;

      sub = micStream.listen(
        (chunk) {
          bytes.addAll(chunk);
        },
        onError: (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await Future.any([
        Future.delayed(Duration(seconds: captureSeconds)),
        completer.future,
      ]);

      await sub.cancel();

      final normalized = _bytesToSamples(bytes);
      if (normalized.isEmpty || _rms(normalized) < 1e-5) {
        // Fallback: record to temp WAV and read samples (helps on Windows).
        final fileSamples = await _captureToFile(recorder);
        if (fileSamples.isEmpty) {
          return RoomCalibrationResult.failure(
            'Signal too low or mic muted. Check input device / privacy settings, then try again.',
          );
        }
        return _analyze(fileSamples);
      }

      return _analyze(normalized);
    } catch (e) {
      return RoomCalibrationResult.failure('Mic capture failed: $e');
    } finally {
      if (started) {
        try {
          await recorder.stop();
        } catch (_) {}
      }
      try {
        await recorder.dispose();
      } catch (_) {}
    }
  }

  Future<InputDevice?> _pickDevice(AudioRecorder recorder) async {
    try {
      final devices = await recorder.listInputDevices();
      if (devices.isEmpty) return null;
      if (preferredDeviceId != null) {
        final match =
            devices.firstWhere((d) => d.id == preferredDeviceId, orElse: () => devices.first);
        return match;
      }
      // Prefer desktop loopback if exposed (e.g., Stereo Mix / loopback).
      final loopback = devices.firstWhere(
        (d) => d.label.toLowerCase().contains('loopback') ||
            d.label.toLowerCase().contains('stereo mix') ||
            d.label.toLowerCase().contains('what u hear'),
        orElse: () => devices.first,
      );
      return loopback;
    } catch (_) {
      return null;
    }
  }

  List<double> _bytesToSamples(List<int> bytes) {
    if (bytes.length < 2) return const [];
    final raw = Uint8List.fromList(bytes);
    final sampleCount = raw.lengthInBytes ~/ 2;
    if (sampleCount == 0) return const [];
    final samples = Int16List.view(raw.buffer, raw.offsetInBytes, sampleCount);
    return List<double>.generate(sampleCount, (i) => samples[i] / 32768.0);
  }

  Future<List<double>> _captureToFile(AudioRecorder recorder) async {
    final dir = await Directory.systemTemp.createTemp('room_calib');
    final file = File(p.join(dir.path, 'capture.wav'));
    await recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
      path: file.path,
    );
    await Future.delayed(Duration(seconds: captureSeconds));
    await recorder.stop();
    if (!file.existsSync()) return const [];
    final bytes = await file.readAsBytes();
    // Basic WAV header skip (44 bytes typical).
    if (bytes.length <= 44) return const [];
    return _bytesToSamples(bytes.sublist(44));
  }

  RoomCalibrationResult _analyze(List<double> samples) {
    if (samples.isEmpty) {
      return RoomCalibrationResult.failure('Mic capture empty.');
    }

    final rms = _rms(samples);
    final rmsDb = 20 * log(rms + 1e-9) / ln10;
    if (rmsDb < -50) {
      return RoomCalibrationResult.failure(
        'Signal too low (${rmsDb.toStringAsFixed(1)} dBFS).',
      );
    }

    const block = 2048;
    const hop = 1024;
    final bandEnergy = {for (final b in _bands) b: <double>[]};

    for (var i = 0; i + block <= samples.length; i += hop) {
      final window = samples.sublist(i, i + block);
      for (final band in _bands) {
        bandEnergy[band]!.add(_goertzel(window, sampleRate, band.toDouble()));
      }
    }

    final bandDb = <int, double>{};
    bandEnergy.forEach((freq, values) {
      if (values.isEmpty) {
        bandDb[freq] = -120;
        return;
      }
      final avg = values.reduce((a, b) => a + b) / values.length;
      bandDb[freq] = 20 * log(avg + 1e-12) / ln10;
    });

    final suggested = _suggestCorrections(bandDb);

    return RoomCalibrationResult(
      bandDb: bandDb,
      suggestedGains: suggested,
      rmsDb: rmsDb,
      success: true,
      error: null,
    );
  }

  Map<int, double> _suggestCorrections(Map<int, double> bandDb) {
    if (bandDb.isEmpty) return const {};
    final values = bandDb.values.toList()..sort();
    final median = values[values.length ~/ 2];
    final result = <int, double>{};
    bandDb.forEach((freq, db) {
      final gain = (median - db).clamp(-maxCorrectionDb, maxCorrectionDb);
      result[freq] = double.parse(gain.toStringAsFixed(1));
    });
    return result;
  }

  double _rms(List<double> samples) {
    double sum = 0;
    for (final s in samples) {
      sum += s * s;
    }
    return sqrt(sum / samples.length);
  }

  double _goertzel(List<double> samples, int fs, double targetHz) {
    final n = samples.length;
    if (n == 0) return 0;
    final k = (0.5 + (n * targetHz) / fs).floor();
    final w = (2 * pi / n) * k;
    final cosine = cos(w);
    final sine = sin(w);
    final coeff = 2 * cosine;

    double q0 = 0;
    double q1 = 0;
    double q2 = 0;

    for (final x in samples) {
      q0 = coeff * q1 - q2 + x;
      q2 = q1;
      q1 = q0;
    }

    final real = q1 - q2 * cosine;
    final imag = q2 * sine;
    return sqrt(real * real + imag * imag) / n;
  }
}
