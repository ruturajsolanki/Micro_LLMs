import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/utils/logger.dart';
import 'domain/entities/app_settings.dart';
import 'presentation/blocs/model/model_bloc.dart';
import 'presentation/blocs/settings/settings_bloc.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/onboarding_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/pages/device_compatibility_page.dart';
import 'presentation/pages/benchmark_page.dart';
import 'presentation/theme/app_theme.dart';

/// Application entry point.
/// 
/// Initializes dependencies, sets up system UI, and launches the app.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize dependencies
  await initializeDependencies();
  
  // Set preferred orientations (portrait only for mobile)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  
  AppLogger.i('Starting MicroLLM app');
  
  runApp(const MicroLLMApp());
}

/// Root application widget.
class MicroLLMApp extends StatelessWidget {
  const MicroLLMApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // Global BLoCs that persist across navigation
        BlocProvider<ModelBloc>(
          create: (_) => sl<ModelBloc>()..add(const ModelCheckRequested()),
        ),
        BlocProvider<SettingsBloc>(
          create: (_) => sl<SettingsBloc>()..add(const SettingsLoadRequested()),
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          return MaterialApp(
            title: 'MicroLLM',
            debugShowCheckedModeBanner: false,
            
            // Theme configuration
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: _getThemeMode(settingsState.settings.themePreference),
            
            // Navigation
            initialRoute: '/',
            onGenerateRoute: _onGenerateRoute,
          );
        },
      ),
    );
  }
  
  ThemeMode _getThemeMode(ThemePreference preference) {
    switch (preference) {
      case ThemePreference.system:
        return ThemeMode.system;
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
    }
  }
  
  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        // Entry point - check model status
        return MaterialPageRoute(
          builder: (context) => BlocBuilder<ModelBloc, ModelState>(
            builder: (context, state) {
              // Show onboarding if model not ready
              if (!state.isReady) {
                return const OnboardingPage();
              }
              return const ChatPage();
            },
          ),
        );
      
      case '/chat':
        return MaterialPageRoute(
          builder: (_) => const ChatPage(),
        );
      
      case '/settings':
        return MaterialPageRoute(
          builder: (_) => const SettingsPage(),
        );
      
      case '/device-compatibility':
        return MaterialPageRoute(
          builder: (_) => const DeviceCompatibilityPage(),
        );
      
      case '/benchmark':
        return MaterialPageRoute(
          builder: (_) => const BenchmarkPage(),
        );
      
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(
              child: Text('Page not found'),
            ),
          ),
        );
    }
  }
}
