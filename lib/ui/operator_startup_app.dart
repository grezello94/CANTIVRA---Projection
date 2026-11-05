import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/operator_bootstrap.dart';
import '../presentation/live_controller.dart';
import '../presentation/slide_surface.dart';
import 'operator_app.dart';

/// A library failure must not remove controls for an already running output.
/// This screen can inspect and control that renderer; it never opens a new one.
class OperatorStartupApp extends StatelessWidget {
  const OperatorStartupApp({super.key, required this.bootstrap});

  final OperatorBootstrap bootstrap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: bootstrap,
    builder: (context, _) {
      final workspace = bootstrap.workspace;
      if (workspace != null) return CantivraApp(controller: workspace);
      final live = bootstrap.recoveryLive;
      final canControl = bootstrap.output?.canControl ?? false;
      void command(Future<bool> Function() action, {bool emergency = false}) =>
          unawaited(
            bootstrap.performOutputAction(action, emergency: emergency),
          );
      Future<bool> emergencyStop() async {
        final active = bootstrap.workspace?.live ?? bootstrap.recoveryLive;
        return active == null ? false : active.emergencyStop();
      }

      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Cantivra',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
            surface: const Color(0xff151a22),
          ),
          scaffoldBackgroundColor: const Color(0xff10141b),
        ),
        builder: (context, child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f12): () {
              if (canControl) command(emergencyStop, emergency: true);
            },
          },
          child: child ?? const SizedBox.shrink(),
        ),
        home: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Builder(
                      builder: (context) {
                        final scheme = Theme.of(context).colorScheme;
                        final information = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Image.asset(
                              'assets/images/logo.png',
                              height: 64,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.shield_outlined,
                                color: scheme.primary,
                                size: 38,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              bootstrap.startupError == null
                                  ? 'Opening Cantivra'
                                  : 'Your library needs attention',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              bootstrap.startupError == null
                                  ? 'Loading your local service and checking for an existing presentation.'
                                  : 'Your library could not open. Your existing files have been preserved. You can still control an available presentation while checking the storage problem.',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 22),
                            if (bootstrap.loading) ...[
                              const LinearProgressIndicator(),
                              const SizedBox(height: 12),
                              const Text('Opening the library…'),
                            ] else
                              FilledButton.icon(
                                key: const ValueKey('retry-library'),
                                onPressed: () => unawaited(bootstrap.retry()),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry library'),
                              ),
                            if (bootstrap.startupError case final failure?) ...[
                              const SizedBox(height: 20),
                              ExpansionTile(
                                title: const Text('Error details'),
                                tilePadding: EdgeInsets.zero,
                                children: [SelectableText(failure)],
                              ),
                            ],
                          ],
                        );
                        final output = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.live_tv, size: 20),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'EXISTING PRESENTATION',
                                    style: TextStyle(letterSpacing: 1.2),
                                  ),
                                ),
                                if (bootstrap.reconnecting)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SlideSurface(
                                  slide: live?.frame.slide,
                                  mode: live?.frame.mode ?? OutputMode.black,
                                  backgroundVisible:
                                      live?.frame.backgroundVisible ?? true,
                                  canvasScale:
                                      bootstrap.output?.canvasScale ?? 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              bootstrap.output?.statusLabel ??
                                  'Output location unavailable',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              key: const ValueKey('recovery-emergency'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xffae303c),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(18),
                              ),
                              onPressed: canControl && live != null
                                  ? () =>
                                        command(emergencyStop, emergency: true)
                                  : null,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('Emergency black · F12'),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton(
                                  key: const ValueKey('recovery-black'),
                                  onPressed:
                                      canControl && live != null && !live.busy
                                      ? () => command(live.black)
                                      : null,
                                  child: const Text('Black screen'),
                                ),
                                OutlinedButton(
                                  key: const ValueKey('recovery-restore'),
                                  onPressed:
                                      canControl &&
                                          live != null &&
                                          !live.busy &&
                                          live.frame.slide != null
                                      ? () => command(live.restore)
                                      : null,
                                  child: const Text('Restore captured slide'),
                                ),
                                TextButton.icon(
                                  key: const ValueKey('recovery-reconnect'),
                                  onPressed:
                                      !bootstrap.loading &&
                                          !bootstrap.reconnecting &&
                                          !canControl &&
                                          bootstrap.output != null
                                      ? () => unawaited(
                                          bootstrap.reconnectExisting(),
                                        )
                                      : null,
                                  icon: const Icon(Icons.link),
                                  label: const Text(
                                    'Reconnect existing output',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'These controls use the captured presentation. They do not open or move a display. Restore requires an explicit action.',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            if (bootstrap.actionError ?? live?.error
                                case final failure?) ...[
                              const SizedBox(height: 12),
                              Text(
                                failure,
                                style: TextStyle(color: scheme.error),
                              ),
                            ],
                          ],
                        );
                        return LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth < 850
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    information,
                                    const SizedBox(height: 36),
                                    output,
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: information),
                                    const SizedBox(width: 56),
                                    Expanded(child: output),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
