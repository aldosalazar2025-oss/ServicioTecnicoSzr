import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Activación LOCAL. No es una licencia online ni resistente a manipulación.
class LicenseService {
  static const _salt = 'szr-license-v92-2026';
  static const _passwordDigest = '6356eb1e5a87814f9dc158f7c2019477817bc3646dc5f155d8ae46b411860666';
  static const _expiryKey = 'szr_license_expiry_v92';
  static const _failKey = 'szr_license_failures_v92';
  static const _lockedKey = 'szr_license_locked_until_v92';

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.tryParse(prefs.getString(_expiryKey) ?? '');
    return expiry != null && DateTime.now().isBefore(expiry);
  }

  static Future<DateTime?> expiry() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_expiryKey) ?? '');
  }

  static Future<DateTime?> blockedUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final value = DateTime.tryParse(prefs.getString(_lockedKey) ?? '');
    if (value == null || !DateTime.now().isBefore(value)) {
      await prefs.remove(_lockedKey);
      if (value != null) await prefs.setInt(_failKey, 0);
      return null;
    }
    return value;
  }

  static Future<int> remainingAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return (3 - (prefs.getInt(_failKey) ?? 0)).clamp(0, 3);
  }

  static Future<String?> activate(String password, int days) async {
    if (await blockedUntil() != null) return 'Activación bloqueada hasta mañana.';
    if (days < 1 || days > 3650) return 'Ingresa entre 1 y 3650 días.';
    final prefs = await SharedPreferences.getInstance();
    final hashed = sha256.convert(utf8.encode('$_salt$password')).toString();
    if (hashed != _passwordDigest) {
      final failures = (prefs.getInt(_failKey) ?? 0) + 1;
      await prefs.setInt(_failKey, failures);
      if (failures >= 3) {
        final now = DateTime.now();
        await prefs.setString(_lockedKey, DateTime(now.year, now.month, now.day + 1).toIso8601String());
        return '3 intentos fallidos. Bloqueado hasta mañana.';
      }
      return 'Contraseña incorrecta. Quedan ${3 - failures} intentos.';
    }
    final now = DateTime.now();
    final oldExpiry = DateTime.tryParse(prefs.getString(_expiryKey) ?? '');
    final start = oldExpiry != null && oldExpiry.isAfter(now) ? oldExpiry : now;
    await prefs.setString(_expiryKey, start.add(Duration(days: days)).toIso8601String());
    await prefs.setInt(_failKey, 0);
    await prefs.remove(_lockedKey);
    return null;
  }
}
