import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Replace Flutter's default red/blank error box with a neutral, recoverable
  // screen. During auth transitions (e.g. sign-out) a widget may briefly fail
  // to build while providers empty out; without this, a release build shows a
  // blank grey screen instead of recovering to the login page.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) FlutterError.presentError(details);
    return const _RecoveryScreen();
  };

  // Swallow uncaught async/platform-callback errors so they can never terminate
  // the app. In particular, go_router 14.x can throw `Bad state: No element`
  // from `_findCurrentNavigator` when the system back button is dispatched while
  // the route match list is momentarily empty (during sign-out shell teardown).
  // That error surfaces on the platform back-button channel, not the widget
  // build path, so it bypasses ErrorWidget.builder and would otherwise finish
  // the Android Activity (app closes to launcher). Returning `true` marks it
  // handled and keeps the app alive so the auth redirect can settle on /login.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kDebugMode) FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stack) {
    debugPrint('Handled uncaught error: $error');
    return true;
  };

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Offline cache for mobile/web (works without connectivity where supported).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: B2bApp()));
}

/// Neutral placeholder shown in place of a failed widget subtree. It carries no
/// Material/Directionality dependency of its own so it renders safely even when
/// the error occurs above the app's providers.
class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFFF6F8F6),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1976D2)),
            ),
          ),
        ),
      ),
    );
  }
}
