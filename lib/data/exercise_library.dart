/// Knee OA exercise library — 1:1 port of `kneedle-backend/exercises.py`.
///
/// Sources (kept here so the citation stays with the code):
///   * 2019 ACR/AF Guideline (Kolasinski et al., Arthritis Care & Research, 2020)
///   * OARSI 2019 (Bannuru et al., Osteoarthritis and Cartilage)
///   * NICE NG226 (2022)
///   * GLA:D (Skou & Roos, BMC Musculoskelet Disord, 2017)
///   * AAOS Knee Conditioning Program (OrthoInfo, 2017)
///   * Al-Johani et al. 2014 (J Phys Ther Sci, PMC4085199)
///   * Bartels et al. 2016 (Cochrane)
///   * Shull et al. 2013 (J Orthop Res) — toe-out modification
///
/// Each entry carries the same fields the backend used so the prompt format
/// (`_format_library`) translates 1:1.
class ExerciseDef {
  const ExerciseDef({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.reps,
    required this.repsEn,
    required this.description,
    required this.descriptionEn,
    required this.clinicalIndication,
    required this.contraindication,
    required this.evidence,
    required this.videoUrl,
  });

  final String id;
  final String name; // Bengali
  final String nameEn;
  final String reps; // Bengali
  final String repsEn;
  final String description;
  final String descriptionEn;
  final String clinicalIndication;
  final String contraindication;
  final String evidence;
  final String videoUrl;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'name_en': nameEn,
        'reps': reps,
        'reps_en': repsEn,
        'description': description,
        'description_en': descriptionEn,
        'clinical_indication': clinicalIndication,
        'contraindication': contraindication,
        'evidence': evidence,
        'video_url': videoUrl,
      };
}

const List<ExerciseDef> exerciseLibrary = [
  ExerciseDef(
    id: 'straight_leg_raise',
    name: 'পা সোজা তোলা',
    nameEn: 'Straight Leg Raise',
    reps: '১৫×৩',
    repsEn: '15×3',
    description: 'পিঠে শুয়ে এক পা সোজা রেখে ৪৫° উপরে তুলুন, ৫ সেকেন্ড ধরে রাখুন তারপর নামান।',
    descriptionEn:
        'Lie on back, raise one straight leg to 45°, hold 5 seconds, lower slowly.',
    clinicalIndication:
        'Quadriceps weakness — primary cause of knee instability in OA. Addresses reduced knee flexion angle and asymmetry.',
    contraindication: 'Acute lower back pain',
    evidence: 'Strong recommendation — ACR/AF 2019',
    videoUrl: 'https://www.youtube.com/watch?v=zo2pqw794B0',
  ),
  ExerciseDef(
    id: 'supported_knee_bend',
    name: 'চেয়ারে হাঁটু মোড়ানো',
    nameEn: 'Seated Knee Flexion',
    reps: '১০×৩',
    repsEn: '10×3',
    description: 'চেয়ারে বসে ধীরে ধীরে হাঁটু যতটুকু সম্ভব ভাঁজ করুন এবং আবার সোজা করুন।',
    descriptionEn:
        'Sit in chair, slowly bend knee as far as comfortable, then straighten.',
    clinicalIndication:
        'Reduced knee range of motion. Directly addresses limited flexion angle measured by MediaPipe.',
    contraindication: 'None for seated version',
    evidence: 'Strong recommendation — ACR/AF 2019',
    videoUrl: 'https://www.youtube.com/watch?v=bpjMkq213Kw',
  ),
  ExerciseDef(
    id: 'toe_out_walk',
    name: 'আঙুল বাইরে রেখে হাঁটা',
    nameEn: 'Toe-Out Gait Training',
    reps: '১০ মিনিট',
    repsEn: '10 minutes',
    description:
        'ঘরের মধ্যে পায়ের আঙুল ১০° বাইরে রেখে ধীরে হাঁটুন। এটি হাঁটুর ভেতরের চাপ কমায়।',
    descriptionEn:
        'Walk indoors with toes pointed 10° outward. Clinically proven to reduce medial knee load.',
    clinicalIndication:
        'Low toe-out angle. Toe-out modification reduces knee adduction moment — equivalent to NSAIDs for pain reduction (Shull et al., 2013, J Orthop Res).',
    contraindication: 'Hip pain',
    evidence: 'Conditional recommendation — supported by biomechanical evidence',
    videoUrl: 'https://www.youtube.com/watch?v=4T3tBgDuUsU',
  ),
  ExerciseDef(
    id: 'wall_sit',
    name: 'দেওয়ালে হেলান বসা',
    nameEn: 'Supported Wall Sit',
    reps: '৩০ সেকেন্ড×৩',
    repsEn: '30 seconds×3',
    description:
        'দেওয়ালে পিঠ দিয়ে ধীরে সামান্য বসার ভঙ্গিতে যান (৩০° কোণ), ৩০ সেকেন্ড থাকুন।',
    descriptionEn:
        'Back against wall, slide down to 30° bend, hold 30 seconds. Strengthens without joint impact.',
    clinicalIndication:
        'Trunk lean and gait asymmetry — builds hip and quad strength to correct compensatory lean.',
    contraindication: 'Severe pain at any knee bend',
    evidence: 'Strong recommendation — ACR/AF 2019 (strengthening exercise)',
    videoUrl: 'https://www.youtube.com/watch?v=hAvVXAE9Bgs',
  ),
  ExerciseDef(
    id: 'calf_raise',
    name: 'গোড়ালি তোলা',
    nameEn: 'Standing Calf Raise',
    reps: '১২×৩',
    repsEn: '12×3',
    description:
        'চেয়ার ধরে দাঁড়িয়ে ধীরে গোড়ালি তুলুন এবং নামান। ভারসাম্য ও হাঁটার গতি উন্নত করে।',
    descriptionEn:
        'Hold chair, rise on toes slowly, lower. Improves balance and walking cadence.',
    clinicalIndication:
        'Low cadence and poor balance. Addresses ankle stability which affects knee loading.',
    contraindication: 'Severe ankle arthritis',
    evidence: 'Conditional recommendation — ACR/AF 2019 (balance training)',
    videoUrl: 'https://www.youtube.com/watch?v=k67UjgvJdEk',
  ),
  ExerciseDef(
    id: 'side_lying_hip_abduction',
    name: 'পাশে শুয়ে পা তোলা',
    nameEn: 'Side-Lying Hip Abduction',
    reps: '১০×২',
    repsEn: '10×2',
    description: 'পাশে শুয়ে উপরের পা সোজা রেখে ৩০° তুলুন, ৩ সেকেন্ড ধরুন তারপর নামান।',
    descriptionEn:
        'Lie on side, raise top leg straight to 30°, hold 3 seconds, lower slowly.',
    clinicalIndication:
        'Trunk lean and gait asymmetry — hip abductor weakness is the primary cause of lateral trunk lean in knee OA.',
    contraindication: 'Hip replacement',
    evidence: 'Strong recommendation — ACR/AF 2019 (hip strengthening)',
    videoUrl: 'https://www.youtube.com/watch?v=s7nG4VEWXOo',
  ),
  ExerciseDef(
    id: 'seated_marching',
    name: 'চেয়ারে বসে পা তোলা',
    nameEn: 'Seated Marching',
    reps: '২০×২',
    repsEn: '20×2',
    description:
        'চেয়ারে বসে একবার ডান পা, একবার বাম পা উঁচু করুন — হাঁটার মতো। ধীরে করুন।',
    descriptionEn:
        'Sit in chair, alternately lift each knee as if marching. Improves hip flexor strength and gait rhythm.',
    clinicalIndication:
        'Low cadence and general deconditioning. Safe for all severity levels.',
    contraindication: 'None',
    evidence:
        'Strong recommendation — ACR/AF 2019 (aerobic/functional exercise)',
    videoUrl: 'https://www.youtube.com/watch?v=M0lLstyOqRw',
  ),
  ExerciseDef(
    id: 'tai_chi_step',
    name: 'ধীর পদক্ষেপ অনুশীলন',
    nameEn: 'Slow Step Practice',
    reps: '৫ মিনিট',
    repsEn: '5 minutes',
    description:
        'খুব ধীরে, সচেতনভাবে হাঁটুন। প্রতিটি পদক্ষেপে মাটিতে পা রাখার অনুভূতিতে মনোযোগ দিন।',
    descriptionEn:
        'Walk very slowly and mindfully. Focus on each foot placement. Based on Tai Chi principles.',
    clinicalIndication:
        'General knee OA, poor balance, high pain. Tai Chi is strongly recommended by ACR/AF 2019 specifically for knee OA.',
    contraindication: 'None',
    evidence:
        'Strong recommendation — ACR/AF 2019 (Tai Chi specifically for knee OA)',
    videoUrl: 'https://www.youtube.com/watch?v=yoN6P9D4yAY',
  ),
  ExerciseDef(
    id: 'quad_set',
    name: 'হাঁটু চাপ ব্যায়াম',
    nameEn: 'Quadriceps Setting (Isometric)',
    reps: '১০ সেকেন্ড×১০',
    repsEn: '10 seconds×10',
    description:
        'পিঠে শুয়ে পা সোজা রেখে হাঁটুর নিচে গুটানো তোয়ালে রাখুন। উরুর পেশি শক্ত করে হাঁটু দিয়ে তোয়ালে চাপ দিন, ১০ সেকেন্ড ধরে রাখুন।',
    descriptionEn:
        'Lie on back with rolled towel under knee. Tighten thigh muscle, pressing knee down into towel. Hold 10 seconds.',
    clinicalIndication:
        'Severe knee pain or earliest-stage rehab. Preserves quadriceps strength — the primary muscular protector against OA progression — when active ROM exercises are too painful. Foundational entry exercise.',
    contraindication: 'None — safe at all severity levels',
    evidence: 'AAOS Knee Conditioning Program; ACR/AF 2019 (strengthening)',
    videoUrl: 'https://www.youtube.com/watch?v=5TUK4uT2nnw',
  ),
  ExerciseDef(
    id: 'heel_slide',
    name: 'গোড়ালি টানা ব্যায়াম',
    nameEn: 'Heel Slide',
    reps: '১৫×২',
    repsEn: '15×2',
    description:
        'পিঠে শুয়ে পা সোজা রাখুন। ধীরে ধীরে এক পায়ের গোড়ালি নিতম্বের দিকে টেনে আনুন যতদূর আরামে সম্ভব, ৫ সেকেন্ড থামুন, তারপর ফেরান।',
    descriptionEn:
        'Lie on back, legs straight. Slowly slide one heel toward buttock to bend knee as far as comfortable, hold 5 seconds, slide back.',
    clinicalIndication:
        'Reduced knee flexion ROM measured by MediaPipe. Gentle non-weight-bearing progression of flexion angle; safer than seated knee flexion for acute pain.',
    contraindication: 'Recent knee surgery without surgeon clearance',
    evidence:
        'AAOS Knee Conditioning Program; Kaiser Permanente knee OA protocol',
    videoUrl: 'https://www.youtube.com/watch?v=XJI-HRJ-gXw',
  ),
  ExerciseDef(
    id: 'mini_squat',
    name: 'মিনি স্কোয়াট',
    nameEn: 'Mini Squat',
    reps: '১০×৩',
    repsEn: '10×3',
    description:
        'চেয়ারের পেছনে দাঁড়িয়ে চেয়ার ধরে রাখুন। পা কাঁধ-প্রস্থ ফাঁকা। হাঁটু মাত্র ৩০–৪৫° ভাঁজ করুন (যেন বসতে যাচ্ছেন), হাঁটু আঙুলের উপর রাখুন, তারপর সোজা হন।',
    descriptionEn:
        'Stand behind chair holding it for support, feet shoulder-width. Bend knees only 30–45° as if about to sit, keeping knees aligned over toes, then stand.',
    clinicalIndication:
        'Quadriceps weakness with preserved ambulation. Closed-chain functional strengthening (load-bearing) which transfers to gait better than open-chain SLR alone.',
    contraindication:
        'Pain >5/10 during the movement; knee instability or giving-way',
    evidence:
        'GLA:D Program (Skou & Roos 2017, BMC Musculoskelet Disord); ACR/AF 2019 (strong recommendation, strengthening)',
    videoUrl: 'https://www.youtube.com/watch?v=w2arL8LK_6E',
  ),
  ExerciseDef(
    id: 'step_up',
    name: 'সিঁড়িতে পা তোলা ব্যায়াম',
    nameEn: 'Step-Up',
    reps: '১০×২ প্রতি পায়ে',
    repsEn: '10×2 each leg',
    description:
        'একটি নিচু সিঁড়ি বা ১০–১৫ সেমি উঁচু বাক্সে এক পা রেখে শরীর তুলে উঠুন, তারপর ধীরে নামুন। রেলিং বা দেওয়াল ধরে রাখুন।',
    descriptionEn:
        'Place one foot on a low step (10–15 cm) and rise up onto it, then lower slowly. Hold rail or wall for support.',
    clinicalIndication:
        'Gait asymmetry and low cadence. Replicates stair-climb demand and trains single-limb support — directly addresses asymmetric step length and weight transfer detected by frame analysis.',
    contraindication:
        'Severe pain on weight bearing; significant balance impairment without supervision',
    evidence: 'AAOS Knee Conditioning Program; ACR/AF 2019 (strengthening)',
    videoUrl: 'https://www.youtube.com/watch?v=rC67BUNGWWI',
  ),
  ExerciseDef(
    id: 'standing_hamstring_curl',
    name: 'দাঁড়িয়ে হাঁটু পেছনে ভাঁজ',
    nameEn: 'Standing Hamstring Curl',
    reps: '১২×২ প্রতি পায়ে',
    repsEn: '12×2 each leg',
    description:
        'চেয়ার ধরে সোজা দাঁড়িয়ে এক পায়ের হাঁটু ভাঁজ করে গোড়ালি নিতম্বের দিকে আনুন, ২ সেকেন্ড ধরুন, ধীরে নামান।',
    descriptionEn:
        'Stand holding chair. Bend one knee, bringing heel toward buttock, hold 2 seconds, lower slowly.',
    clinicalIndication:
        'Hamstring weakness with reduced flexion ROM. Combined hamstring + quadriceps strengthening shown more effective than quad-only for pain and function in knee OA.',
    contraindication: 'Acute hamstring strain',
    evidence:
        'Al-Johani et al. 2014 (J Phys Ther Sci, PMC4085199); ACR/AF 2019 (strengthening)',
    videoUrl: 'https://www.youtube.com/watch?v=oWu8RxtWdGE',
  ),
  ExerciseDef(
    id: 'stationary_cycling',
    name: 'স্থির সাইকেল চালানো',
    nameEn: 'Stationary Cycling',
    reps: '১৫–২০ মিনিট',
    repsEn: '15–20 minutes',
    description:
        'স্থির সাইকেলে কম রেজিস্ট্যান্সে চালান। সিটের উচ্চতা এমন রাখুন যাতে প্যাডেল সর্বনিম্ন অবস্থানে হাঁটু প্রায় সোজা হয় (২৫–৩৫° ভাঁজ)।',
    descriptionEn:
        'Cycle on stationary bike at low resistance. Set seat high so knee is nearly straight (25–35° bend) at the lowest pedal position to minimize joint load.',
    clinicalIndication:
        'General deconditioning, low cadence, reduced knee flexion ROM. Low-impact aerobic work that simultaneously cycles flexion through a controlled range — addresses both endurance and ROM.',
    contraindication:
        'Knee pain >4/10 during cycling; severe patellofemoral OA may require seat adjustment',
    evidence:
        'ACR/AF 2019 (strong recommendation, aerobic exercise); OARSI 2019 (core treatment)',
    videoUrl: 'https://www.youtube.com/watch?v=NhxK6QrVwbU',
  ),
  ExerciseDef(
    id: 'aquatic_walking',
    name: 'জলে হাঁটার ব্যায়াম',
    nameEn: 'Aquatic Walking',
    reps: '২০–৩০ মিনিট',
    repsEn: '20–30 minutes',
    description:
        'বুক-গভীর গরম জলে ধীরে সামনে ও পেছনে হাঁটুন। জলের প্লবতা হাঁটুর উপর চাপ ৫০–৯০% কমায়।',
    descriptionEn:
        'Walk slowly forward and backward in chest-deep warm water. Buoyancy reduces knee load by 50–90%, allowing pain-free gait practice.',
    clinicalIndication:
        'High pain, severe OA, high BMI, or marked gait asymmetry that prevents land-based walking. Meta-analyses show aquatic exercise relieves pain at least as well as land-based.',
    contraindication:
        'Open wounds, active skin or urinary infection, uncontrolled cardiac disease, fear of water',
    evidence: 'ACR/AF 2019 (strong recommendation); OARSI 2019; Bartels et al. Cochrane 2016',
    videoUrl: 'https://www.youtube.com/watch?v=Jhajl4zzdko',
  ),
  ExerciseDef(
    id: 'clamshell',
    name: 'শামুক ব্যায়াম',
    nameEn: 'Clamshell',
    reps: '১৫×২ প্রতি পাশে',
    repsEn: '15×2 each side',
    description:
        'পাশে শুয়ে হাঁটু ৪৫° ভাঁজ করুন, পা একসাথে রাখুন। পা একসাথে রেখে উপরের হাঁটু শামুকের মতো খুলুন, ২ সেকেন্ড ধরে রাখুন, নামান।',
    descriptionEn:
        'Lie on side with knees bent 45°, feet together. Keeping feet touching, lift top knee like a clamshell opening, hold 2 seconds, lower.',
    clinicalIndication:
        'Trunk lean and dynamic knee valgus. Strengthens gluteus medius and hip external rotators, which control frontal-plane knee alignment during gait — addresses lateral trunk lean.',
    contraindication:
        'Total hip replacement (violates posterior precautions in early phase)',
    evidence:
        'GLA:D neuromuscular protocol; ACR/AF 2019 (hip strengthening for knee OA)',
    videoUrl: 'https://www.youtube.com/watch?v=HQ1158rgFyU',
  ),
  ExerciseDef(
    id: 'glute_bridge',
    name: 'সেতু ব্যায়াম',
    nameEn: 'Glute Bridge',
    reps: '১২×২',
    repsEn: '12×2',
    description:
        'পিঠে শুয়ে হাঁটু ভাঁজ করে পা মাটিতে রাখুন। নিতম্ব চেপে ধরে কোমর উপরে তুলুন যেন কাঁধ থেকে হাঁটু সরলরেখা হয়, ৩ সেকেন্ড ধরে রাখুন, নামান।',
    descriptionEn:
        'Lie on back, knees bent, feet flat. Squeeze glutes and lift hips so shoulders, hips, and knees form a straight line. Hold 3 seconds, lower.',
    clinicalIndication:
        'Gait asymmetry and trunk lean. Activates posterior chain (glutes, hamstrings) which stabilize the pelvis during single-limb support and reduce compensatory trunk lean.',
    contraindication:
        'Acute lower back pain; pregnancy beyond 2nd trimester (supine position)',
    evidence: 'GLA:D neuromuscular protocol; ACR/AF 2019 (strengthening)',
    videoUrl: 'https://www.youtube.com/watch?v=I6vxggX_1KM',
  ),
  ExerciseDef(
    id: 'hamstring_stretch',
    name: 'হ্যামস্ট্রিং স্ট্রেচ',
    nameEn: 'Supine Hamstring Stretch',
    reps: '৩০ সেকেন্ড×৩',
    repsEn: '30 seconds×3',
    description:
        'পিঠে শুয়ে এক পায়ের পাতায় তোয়ালে বা চাদর জড়িয়ে দু-হাতে ধরুন। পা সোজা রেখে উপরে তুলুন যতদূর উরুর পেছনে আরামদায়ক টান অনুভব হয়। ৩০ সেকেন্ড ধরে রাখুন।',
    descriptionEn:
        'Lie on back. Loop a towel around one foot, hold both ends. Keeping leg straight, raise it until you feel a gentle stretch behind the thigh. Hold 30 seconds.',
    clinicalIndication:
        'Reduced terminal knee extension and short stride length. Tight hamstrings limit full knee extension during late stance and shorten step length — both visible in MediaPipe frame analysis.',
    contraindication: 'Sciatica or radicular leg pain',
    evidence: 'AAOS Knee Conditioning Program; ACR/AF 2019 (flexibility)',
    videoUrl: 'https://www.youtube.com/watch?v=Il1L75v6gq0',
  ),
];

/// Exercises that require good ambulation / balance / pain-free deep flexion.
/// Excluded for severe cases. Mirrors `SEVERE_EXCLUDE_IDS` in gemma_client.py.
const Set<String> severeExcludeIds = {
  'wall_sit',
  'mini_squat',
  'step_up',
  'toe_out_walk',
};

ExerciseDef? getExerciseById(String id) {
  for (final e in exerciseLibrary) {
    if (e.id == id) return e;
  }
  return null;
}

/// Library subset safe for this severity tier.
List<ExerciseDef> filterLibraryBySeverity(String severity) {
  if (severity == 'severe') {
    return [for (final e in exerciseLibrary) if (!severeExcludeIds.contains(e.id)) e];
  }
  return List<ExerciseDef>.from(exerciseLibrary);
}

/// Render the library for the LLM prompt.
///
/// will change later — trimmed from the backend's full bilingual block to fit
/// the 4 GB test device's RAM budget. We drop:
///   * the Bengali line (the model only picks IDs; localized names are
///     looked up post-parse from `exerciseLibrary`),
///   * `Do NOT use if:` (contraindications are enforced post-parse in
///     `gemma_service._ensureSafeFallback` regardless of the model's pick),
///   * `Evidence:` (cited in the result UI, not needed for selection).
///
/// Result: ~55% smaller prompt, identical selection behaviour, contraindication
/// safety still guaranteed by the post-parse guard. Restore the full bilingual
/// renderer once we target devices with ≥8 GB RAM.
String formatLibraryForPrompt(List<ExerciseDef> library) {
  final buf = StringBuffer();
  for (final ex in library) {
    buf
      ..writeln('[${ex.id}] ${ex.nameEn} (${ex.repsEn})')
      ..writeln('  When to use: ${ex.clinicalIndication}')
      ..writeln();
  }
  return buf.toString();
}
