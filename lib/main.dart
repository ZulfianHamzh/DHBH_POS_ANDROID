import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'providers/pos_provider.dart';
import 'providers/connectivity_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_app_screen.dart';
import 'utils/app_theme.dart';
import 'services/bluetooth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // CRITICAL: Configure global HTTP client with aggressive timeouts
  HttpOverrides.global = _CustomHttpOverrides();

  // Optimize for Android tablets with limited RAM (2GB)
  // Handle memory pressure to prevent OOM crashes
  // SystemChannels.memoryPressure.setMessageHandler((dynamic message) async {
  //   debugPrint('[DHBH] Memory pressure received, clearing caches');
  //   // Clear image cache
  //   PaintingBinding.instance.imageCache.clear();
  //   PaintingBinding.instance.imageCache.clearLiveImages();
  // });
  
  // Set up error handling for uncaught exceptions — log to console AND to a
  // file (%TEMP%\dhbh_flutter_errors.log) so layout/overflow errors can be
  // inspected later even when the console buffer has scrolled.
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrintStack(
      label: '[DHBH] Flutter Error: ${details.exception}',
      stackTrace: details.stack,
    );
    try {
      final message = StringBuffer()
        ..writeln('==== ${DateTime.now().toIso8601String()} ====')
        ..writeln(details.exception)
        ..writeln('Context: ${details.context}');
      final info = details.informationCollector;
      if (info != null) {
        try {
          final nodes = info();
          for (final n in nodes) {
            message.writeln(n.toStringDeep());
          }
        } catch (_) {}
      }
      message.writeln(details.stack ?? '');
      message.writeln();
      final dir = Directory.systemTemp;
      final f = File('${dir.path}${Platform.pathSeparator}dhbh_flutter_errors.log');
      f.writeAsStringSync(message.toString(), mode: FileMode.append);
    } catch (_) {
      // never let logging break the app
    }
  };

  // Initialize Bluetooth service early
  final btService = BluetoothService();
  try {
    await btService.initialize().timeout(const Duration(seconds: 3));
    debugPrint('[DHBH] ✓ Bluetooth service initialized');
  } catch (e) {
    debugPrint('[DHBH] ⚠️ Bluetooth init (non-critical): $e');
  }
  
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Supabase initialization timeout');
      },
    );
    debugPrint('[DHBH] ✓ Supabase initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('[DHBH] ⚠️ Supabase initialization failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }
  
  runApp(const ProviderScope(child: DHBHApp()));
}

/// Custom HTTP overrides to enforce connection timeouts globally
/// This prevents socket hangs during DNS resolution, TCP handshake, and TLS establishment
class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    
    // Set aggressive timeouts to prevent socket hangs
    client.connectionTimeout = const Duration(seconds: 5);
    
    debugPrint('[HTTP] ✓ Global HTTP client configured with 5-second connection timeout');
    return client;
  }
}

class DHBHApp extends StatelessWidget {
  const DHBHApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DHBH App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          primary: AppColors.primaryGreen,
        ),
        textTheme: GoogleFonts.montserratTextTheme(),
        scaffoldBackgroundColor: AppColors.backgroundLight,
      ),
      home: _AppGate(),
    );
  }
}

class _AppGate extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<_AppGate> {
  @override
  void initState() {
    super.initState();
    // Defer so provider state isn't modified during the build phase.
    // Riverpod 2.x throws "Tried to modify a provider while the widget tree
    // was building" if a provider is changed inside initState/build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(posProvider.notifier).checkSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final posState = ref.watch(posProvider);
    final connectivityState = ref.watch(connectivityProvider);

    // Determine the screen to show
    Widget screenContent;

    if (posState.currentUser != null) {
      screenContent = const MainAppScreen();
    } else {
      screenContent = const LoginScreen();
    }

    final isOnline = connectivityState.valueOrNull ?? false;

    return Stack(
      children: [
        screenContent,
        // Offline banner
        if (!isOnline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                color: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Tidak ada koneksi internet',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
