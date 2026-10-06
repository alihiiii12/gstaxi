import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// نغمات تنبيه داخل التطبيق (نغمة تنبيه موحّدة للطلب/القبول/بدء الرحلة).
class AppAlertSound {
  AppAlertSound._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _ready = false;

  /// رنين الطلب الفوري (كامل) + نسخة قصيرة لباقي التنبيهات.
  static const _ringtone = 'sounds/gs_ringtone.mp3';
  static const _notify = 'sounds/gs_notify.mp3';
  static const _tripFinished = 'sounds/trip_finished.wav';

  static final Map<String, DateTime> _lastPlayed = {};

  /// استدعِها مرة عند بدء التطبيق (main).
  static Future<void> ensureInitialized() async {
    if (_ready) return;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('[AppAlertSound] init: $e');
    }
  }

  /// طلب جديد وصل للسائق.
  static Future<void> playNewRequest() =>
      _playAsset(_ringtone, minGapMs: 1500);

  /// قبول السائق للطلب (للراكب).
  static Future<void> playTripAccepted() =>
      _playAsset(_notify, minGapMs: 1500);

  /// بدء الرحلة (سائق + راكب).
  static Future<void> playTripStarted() =>
      _playAsset(_notify, minGapMs: 1500);

  /// أي إشعار آخر يصل والتطبيق مفتوح.
  static Future<void> playNotification() =>
      _playAsset(_notify, minGapMs: 1500);

  /// إيقاف الرنين (بعد قبول/تجاهل الطلب).
  static Future<void> stopRingtone() async {
    if (_current != _ringtone) return;
    try {
      await _player.stop();
    } catch (_) {}
    _current = null;
  }

  static String? _current;

  /// انتهاء الرحلة (راكب وسائق).
  static Future<void> playTripFinished() =>
      _playAsset(_tripFinished, minGapMs: 1500);

  /// زمور خطر SOS.
  static Future<void> playSosDangerHorn() async {
    await ensureInitialized();
    try {
      for (var i = 0; i < 5; i++) {
        await SystemSound.play(SystemSoundType.alert);
        if (i < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 160));
        }
      }
    } catch (_) {}
  }

  static Future<void> _playAsset(String asset, {required int minGapMs}) async {
    await ensureInitialized();
    final now = DateTime.now();
    final last = _lastPlayed[asset];
    if (last != null && now.difference(last).inMilliseconds < minGapMs) {
      return;
    }
    _lastPlayed[asset] = now;

    // لا تقطع رنين طلب جارٍ بنغمة إشعار عادي.
    if (_current == _ringtone &&
        asset != _ringtone &&
        _player.state == PlayerState.playing) {
      return;
    }

    try {
      await _player.stop();
      _current = asset;
      await _player.play(AssetSource(asset));
      return;
    } catch (e) {
      debugPrint('[AppAlertSound] asset $asset failed: $e');
    }

    await _fallbackSystem(asset);
  }

  static Future<void> _fallbackSystem(String asset) async {
    try {
      if (asset == _tripFinished) {
        await SystemSound.play(SystemSoundType.alert);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await SystemSound.play(SystemSoundType.alert);
      } else {
        await SystemSound.play(SystemSoundType.alert);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await SystemSound.play(SystemSoundType.click);
      }
    } catch (_) {}
  }

  /// من بيانات إشعار FCM (إن وُجد kind).
  static Future<void> playForPushData(Map<String, dynamic> data) async {
    final kind = (data['kind'] ?? data['type'] ?? '').toString().toLowerCase();
    if (kind.isEmpty) return;

    if (kind == 'immediate_request' ||
        kind == 'scheduled_request' ||
        (kind.contains('immediate') &&
            (kind.contains('new') ||
                kind.contains('pending') ||
                kind.contains('offer') ||
                kind.contains('broadcast')))) {
      await playNewRequest();
      return;
    }
    if (kind.contains('accepted') ||
        kind.contains('reserved') ||
        kind.contains('driver_accept')) {
      await playTripAccepted();
      return;
    }
    if (kind.contains('arrived') || kind.contains('arrival')) {
      await playTripAccepted();
      return;
    }
    if (kind.contains('start') ||
        kind.contains('running') ||
        kind.contains('trip_started') ||
        kind.contains('began')) {
      await playTripStarted();
      return;
    }
    if (kind.contains('finished') || kind.contains('complete')) {
      await playTripFinished();
      return;
    }
    await playNotification();
  }
}
