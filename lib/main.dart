import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home.dart';
import 'services/license_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE', null);
  final prefs = await SharedPreferences.getInstance();
  runApp(ServiceApp(initialDark: prefs.getBool('dark_mode') ?? true));
}

class ServiceApp extends StatefulWidget {
  final bool initialDark;
  const ServiceApp({super.key, required this.initialDark});
  @override
  State<ServiceApp> createState() => _ServiceAppState();
}

class _ServiceAppState extends State<ServiceApp> {
  late bool dark = widget.initialDark;
  bool? licenseActive;
  @override
  void initState() {
    super.initState();
    LicenseService.isActive().then((ok) {
      if (mounted) setState(() => licenseActive = ok);
    });
  }

  Future<void> changeTheme() async {
    setState(() => dark = !dark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', dark);
  }

  ThemeData makeTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00BEEB), brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0D0D12) : const Color(0xFFF6F7FB),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF17171F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF20202B) : const Color(0xFFF0F1F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Servicio Técnico SZR',
    theme: makeTheme(Brightness.light),
    darkTheme: makeTheme(Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: licenseActive == null
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : licenseActive!
        ? HomeScreen(isDark: dark, onToggleTheme: changeTheme)
        : LicenseGate(onActivated: () => setState(() => licenseActive = true)),
  );
}

class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key, required this.onActivated});
  final VoidCallback onActivated;
  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  final daysController = TextEditingController(text: '30');
  final passwordController = TextEditingController();
  String message = '';
  bool busy = false;
  DateTime? blocked;
  int remaining = 3;

  @override
  void initState() {
    super.initState();
    check();
  }
  Future<void> check() async {
    final until = await LicenseService.blockedUntil();
    final attempts = await LicenseService.remainingAttempts();
    if (mounted) setState(() { blocked = until; remaining = attempts; });
  }
  Future<void> activate() async {
    if (busy || blocked != null) return;
    setState(() => busy = true);
    final days = int.tryParse(daysController.text.trim());
    final result = await LicenseService.activate(passwordController.text, days ?? 0);
    passwordController.clear();
    if (!mounted) return;
    if (result == null) { widget.onActivated(); return; }
    setState(() { message = result; busy = false; });
    await check();
  }
  @override
  void dispose() {
    daysController.dispose();
    passwordController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.admin_panel_settings_outlined, size: 52, color: Color(0xFF00BEEB)),
          const SizedBox(height: 12),
          const Text('ACTIVACIÓN DE LICENCIA', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          const Text('Servicio Técnico SZR', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (blocked != null) ...[
            const Text('Demasiados intentos fallidos. Activación bloqueada hasta el siguiente día.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 14),
          ],
          TextField(controller: daysController, keyboardType: TextInputType.number,
            enabled: blocked == null,
            decoration: const InputDecoration(labelText: 'Cantidad de días de licencia', prefixIcon: Icon(Icons.calendar_month))),
          const SizedBox(height: 16),
          TextField(controller: passwordController, obscureText: true,
            enableSuggestions: false, autocorrect: false, enabled: blocked == null,
            onSubmitted: (_) => activate(),
            decoration: const InputDecoration(labelText: 'Contraseña de administrador', prefixIcon: Icon(Icons.lock_outline))),
          const SizedBox(height: 12),
          if (message.isNotEmpty) Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 8),
          Text('Intentos disponibles: $remaining', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: busy || blocked != null ? null : activate,
            icon: const Icon(Icons.verified_user_outlined), label: const Text('Activar licencia')),
          const SizedBox(height: 12),
          const Text('Los datos del taller no se eliminan al vencer la licencia.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ],
      ))),
    ))),
  );
}
