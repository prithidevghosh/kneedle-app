import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../models/exercise_session.dart';
import '../models/gait_session.dart';
import '../models/medication.dart';
import '../models/pain_entry.dart';
import '../services/gait_service.dart';
import '../services/gemma_service.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';

final gemmaServiceProvider = Provider<GemmaService>((_) => GemmaService.instance);
final voiceServiceProvider = Provider<VoiceService>((_) => VoiceService.instance);
final gaitServiceProvider = Provider<GaitService>((_) => GaitService.instance);

/// One-shot Gemma init + download progress (0..1) for the splash UI.
final gemmaInitProvider = FutureProvider<void>((ref) async {
  await ref.read(gemmaServiceProvider).initialise(
        onDownloadProgress: (p) => ref.read(modelDownloadProgressProvider.notifier).state = p,
      );
});

final modelDownloadProgressProvider = StateProvider<double>((_) => 0);

/// Reactive Hive views — refresh by invalidating these providers when a write
/// happens via the services.
final painEntriesProvider = Provider<List<PainEntry>>(
  (_) => StorageService.recentPainEntries(),
);

final gaitSessionsProvider = Provider<List<GaitSession>>(
  (_) => StorageService.recentGaitSessions(),
);

final exerciseSessionsProvider = Provider<List<ExerciseSession>>(
  (_) => StorageService.recentExerciseSessions(),
);

final medicationsProvider = Provider<List<Medication>>(
  (_) => StorageService.allMedications(),
);

final appointmentsProvider = Provider<List<Appointment>>(
  (_) => StorageService.upcomingAppointments(),
);

/// Bumped after each Hive write to trigger UI refresh.
final dataRevisionProvider = StateProvider<int>((_) => 0);

void bumpData(WidgetRef ref) {
  ref.read(dataRevisionProvider.notifier).state++;
  ref
    ..invalidate(painEntriesProvider)
    ..invalidate(gaitSessionsProvider)
    ..invalidate(exerciseSessionsProvider)
    ..invalidate(medicationsProvider)
    ..invalidate(appointmentsProvider);
}
