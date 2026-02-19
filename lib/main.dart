import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/utils/logger.dart';
import 'domain/entities/app_settings.dart';
import 'presentation/blocs/model/model_bloc.dart';
import 'presentation/blocs/settings/settings_bloc.dart';
import 'presentation/pages/api_setup_page.dart';
import 'presentation/pages/chat_page.dart';
import 'presentation/pages/onboarding_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/pages/device_compatibility_page.dart';
import 'presentation/pages/benchmark_page.dart';
import 'presentation/pages/system_prompts_page.dart';
import 'presentation/pages/v2_history_page.dart';
import 'presentation/pages/v2_home_page.dart';
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
        // V2: Cloud-first entry point
        return MaterialPageRoute(
          builder: (context) => BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              if (settingsState.settings.useCloudProcessing) {
                return const V2HomePage();
              }
              // V1 fallback: check model status
              return BlocBuilder<ModelBloc, ModelState>(
                builder: (context, modelState) {
                  if (!modelState.isReady) {
                    return const OnboardingPage();
                  }
                  return const ChatPage();
                },
              );
            },
          ),
        );

      case '/v2-home':
        return MaterialPageRoute(
          builder: (_) => const V2HomePage(),
        );

      case '/api-setup':
        return MaterialPageRoute(
          builder: (_) => const ApiSetupPage(),
        );

      case '/v2-history':
        return MaterialPageRoute(
          builder: (_) => const V2HistoryPage(),
        );

      case '/v1-home':
        return MaterialPageRoute(
          builder: (_) => BlocBuilder<ModelBloc, ModelState>(
            builder: (context, modelState) {
              if (!modelState.isReady) {
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

      case '/system-prompts':
        return MaterialPageRoute(
          builder: (_) => const SystemPromptsPage(),
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
