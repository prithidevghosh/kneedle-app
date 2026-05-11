/// Patient-facing safety / educational defaults — port of `SAFETY_DEFAULTS`
/// in `kneedle-backend/gemma_client.py`.
///
/// These are clinically conservative fall-backs. The LLM may override with
/// more patient-specific phrasing; if it omits a field we drop in the matching
/// language default so the patient receives complete guidance.
class SafetyText {
  const SafetyText({
    required this.frequency,
    required this.painRule,
    required this.redFlags,
    required this.complementary,
    required this.referralSevere,
    required this.empathy,
    required this.symGood,
    required this.symFair,
    required this.symPoor,
    required this.symUnknown,
  });

  final String frequency;
  final String painRule;
  final String redFlags;
  final String complementary;
  final String referralSevere;
  final String empathy;
  final String symGood;
  final String symFair;
  final String symPoor;
  final String symUnknown;
}

const SafetyText _bn = SafetyText(
  frequency: 'প্রতিদিন একবার, ২ সপ্তাহ ধরে অনুশীলন করুন।',
  painRule: 'ব্যথা ৫/১০-এর বেশি হলে থামুন। হালকা অস্বস্তি স্বাভাবিক।',
  redFlags:
      'হঠাৎ হাঁটু ফুলে গেলে, পা একদম দিতে না পারলে, বা জ্বর হলে অবিলম্বে ডাক্তার দেখান।',
  complementary:
      'ওজন কমানো, হাঁটুতে গরম সেঁক (১৫ মিনিট), এবং প্রয়োজনে নী-ক্যাপ ব্যবহার করুন।',
  referralSevere:
      'তীব্র উপসর্গের কারণে অনুগ্রহ করে একজন অর্থোপেডিক বা ফিজিওথেরাপিস্টের সাথে সরাসরি দেখা করুন।',
  empathy:
      'হাঁটতে কষ্ট হচ্ছে দেখে আমি বুঝতে পারছি — চলুন, ছোট ছোট ধাপে শুরু করি।',
  symGood: '৮০-এর উপরে স্বাভাবিক — আপনার হাঁটার ভারসাম্য ভালো আছে।',
  symFair:
      '৮০-এর উপরে স্বাভাবিক — আপনার স্কোর কিছুটা কম, উন্নতির সুযোগ আছে।',
  symPoor:
      '৮০-এর উপরে স্বাভাবিক — আপনার স্কোর অনেক কম, এই ব্যায়ামগুলি সাহায্য করবে।',
  symUnknown:
      'ভিডিওতে এক পাশের পা পুরোপুরি দেখা যায়নি, তাই সিমমেট্রি স্কোর নির্ভরযোগ্যভাবে মাপা যায়নি।',
);

const SafetyText _hi = SafetyText(
  frequency: 'रोज़ एक बार, २ सप्ताह तक अभ्यास करें।',
  painRule: 'यदि दर्द ५/१० से अधिक हो तो रुकें। हल्की असुविधा सामान्य है।',
  redFlags:
      'अचानक घुटना सूज जाए, पैर पर खड़े न हो पाएं, या बुखार हो तो तुरंत डॉक्टर से मिलें।',
  complementary:
      'वज़न कम करें, घुटने पर गर्म सिकाई (१५ मिनट) करें, और आवश्यकता हो तो नी-कैप का प्रयोग करें।',
  referralSevere:
      'गंभीर लक्षणों के कारण कृपया हड्डी रोग विशेषज्ञ या फिज़ियोथेरेपिस्ट से सीधी मुलाकात करें।',
  empathy:
      'चलने में तकलीफ़ हो रही है यह मैं समझ सकता हूँ — आइए, छोटे क़दमों से शुरुआत करें।',
  symGood: '८० से ऊपर सामान्य — आपका चाल संतुलन अच्छा है।',
  symFair: '८० से ऊपर सामान्य — आपका स्कोर थोड़ा कम है, सुधार की गुंजाइश है।',
  symPoor:
      '८० से ऊपर सामान्य — आपका स्कोर काफी कम है, ये व्यायाम मदद करेंगे।',
  symUnknown:
      'वीडियो में एक तरफ का पैर पूरी तरह दिखाई नहीं दिया, इसलिए सिमेट्री स्कोर भरोसेमंद ढंग से नहीं मापा जा सका।',
);

const SafetyText _en = SafetyText(
  frequency: 'Daily, once a day, for 2 weeks.',
  painRule: 'Stop if pain exceeds 5/10. Mild discomfort is normal.',
  redFlags:
      'See a doctor immediately if your knee swells suddenly, you cannot bear weight, or you develop a fever.',
  complementary:
      'Lose excess weight, apply a warm compress to the knee for 15 minutes, and consider a knee sleeve.',
  referralSevere:
      'Due to severe symptoms, please see an orthopedist or physiotherapist in person.',
  empathy:
      "I can see walking is difficult — let's start with small, gentle steps.",
  symGood: 'Normal is above 80 — your gait balance is good.',
  symFair:
      'Normal is above 80 — your score is a little low, with room to improve.',
  symPoor:
      'Normal is above 80 — your score is well below normal, these exercises will help.',
  symUnknown:
      'One leg was partially occluded in the video, so a reliable symmetry score could not be measured.',
);

const Map<String, SafetyText> safetyDefaults = {
  'bn': _bn,
  'hi': _hi,
  'en': _en,
};

SafetyText safetyFor(String lang) =>
    safetyDefaults[lang] ?? safetyDefaults['bn']!;
SafetyText get safetyEn => safetyDefaults['en']!;
