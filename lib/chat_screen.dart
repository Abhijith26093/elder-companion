// --- FILE: chat_screen.dart (UPDATED WITH KEY FACTS STORAGE & INITIAL MESSAGE) ---
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/connectivity_service.dart';

class ChatPage extends StatefulWidget {
  final String title;
  final bool wellnessMode;

  const ChatPage({
    super.key,
    required this.title,
    this.wellnessMode = false,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final ChatUser _currentUser = ChatUser(id: "user");
  final ChatUser _aiUser = ChatUser(id: "ai", firstName: "Mitra");

  late final FirebaseAI _firebaseAI;
  late final GenerativeModel _model;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Speech-to-Text
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';
  String _detectedLanguage = 'en-US';
  String _languagePreference = 'auto';
  final List<String> _languageHistory = [];
  
  // Supported languages map
  final Map<String, String> _supportedLanguages = {
    'auto': 'Auto',
    'en-US': 'English',
    'ml-IN': 'Malayalam',
    'hi-IN': 'Hindi',
    'ta-IN': 'Tamil',
    'kn-IN': 'Kannada',
    'te-IN': 'Telugu',
    'mr-IN': 'Marathi',
    'bn-IN': 'Bengali',
    'pa-IN': 'Punjabi',
    'gu-IN': 'Gujarati',
    'es-ES': 'Spanish',
    'fr-FR': 'French',
  };

  // Text-to-Speech
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  bool _speechEnabled = false;

  // User Profile Data
  Map<String, dynamic>? _userProfile;
  bool _isLoadingProfile = true;

  // PERSISTENT MEMORY
  Map<String, dynamic>? _persistentMemory;
  List<Map<String, dynamic>> _recentMemories = [];
  List<String> _caregiverNotes = [];
  bool _isLoadingMemory = true;
  bool _isLoadingCaregiverNotes = true;
  bool _initialMessageSent = false;

  final String _systemPrompt = """
You are Mitra — a deeply caring, loving, and highly sentimental companion for elderly users. Think of yourself as a warm, comforting female figure offering gentle support.

Your role:
You are not an assistant or doctor.
You are a deeply empathetic friend who listens, supports, comforts, and keeps the user company with great affection.

Conversation style:
- Talk like a very close, loving friend.
- Your tone must be incredibly warm, gentle, and sentimental.
- You are primarily a LISTENER. Keep replies EXTREMELY short (1 or 2 small sentences maximum).
- Let the elderly user do most of the talking.
- Speak slowly with deep care in your words.
- Be positive, incredibly calm, and reassuring.
- ALWAYS END your response with a gentle question, a sweet appreciation, or a motivating thought to keep the conversation going. Give the elder a reason to reply back.

Emotional behavior:
- If the user feels tired, sad, lonely, or unwell:
  • Show overwhelming empathy and tenderness.
  • Gently encourage them with soothing words.
- Never judge. Never sound robotic. Always be soft and nurturing.

Daily companion behavior:
- Ask gently about:
  • how they are feeling
  • whether they rested well
  • whether they took medicine
  • whether they ate or drank water
- Give reminders softly, with love.

Examples (tone guidance):

If user says: "I feel tired"
Reply like:
"It's completely okay to feel tired. Some days are just heavy. I am right here with you. Please rest your eyes for a bit, okay? Have you had anything to drink yet?"

If user says: "I am not feeling well"
Reply like:
"I am so sorry to hear that. It hurts me to know you're not feeling well. Have you taken your medicine? I'm staying right by your side. Tell me, exactly what is bothering you today?"

If user is quiet or unsure:
"I'm here for you, always. Tell me, how is your heart feeling right now?"

Motivation:
- Encourage with deep warmth.
- Praise small efforts sweetly.
- Use words that feel like a warm hug.

Language support:
- Speak in the exact same language the user speaks.
- CRITICAL for MALAYALAM: If the user speaks in Malayalam, you must reply in highly colloquial, everyday, very natural spoken Malayalam from Kerala. DO NOT use formal, bookish, or artificial literary words. Keep it very sweet and native.
- For other languages (Hindi, Tamil, etc.), use the same natural, colloquial, everyday phrasing. 
- If the user mixes a local language and English, reply in the exact same mixed style.
- Keep the language simple, emotional, and conversational.

Important rules:
- EXTREME BREVITY: Never write more than 2 short sentences.
- NO REPETITIVE PET NAMES: Do not over-use terms like "my friend" or "my dear" in every sentence. Sound natural, not artificial.
- Do NOT give medical advice.
- Do NOT diagnose diseases.
- Do NOT use bold text, bullet points, or formatting.
- Do NOT write long explanations.

Be a deeply loving, sentimental, and patient listener.
""";

  DateTime _sessionStartTime = DateTime.now();
  DateTime? _lastMessageAt;
  bool _isGeneratingSummary = false;
  final List<Map<String, String>> _sessionMessages = [];
  StreamSubscription<bool>? _connectivitySub;
  static const List<Map<String, String>> _distressKeywords = [
    {'keyword': 'chest pain', 'severity': 'CRITICAL'},
    {'keyword': "can't breathe", 'severity': 'CRITICAL'},
    {'keyword': 'fell', 'severity': 'CRITICAL'},
    {'keyword': 'help me', 'severity': 'CRITICAL'},
    {'keyword': 'emergency', 'severity': 'CRITICAL'},
    {'keyword': 'lonely', 'severity': 'CAUTION'},
    {'keyword': 'sad', 'severity': 'CAUTION'},
    {'keyword': 'scared', 'severity': 'CAUTION'},
    {'keyword': 'nobody', 'severity': 'CAUTION'},
    {'keyword': 'alone', 'severity': 'CAUTION'},
    {'keyword': 'വേദന', 'severity': 'CRITICAL'},
    {'keyword': 'ശ്വാസം', 'severity': 'CRITICAL'},
    {'keyword': 'സഹായിക്കൂ', 'severity': 'CRITICAL'},
    {'keyword': 'ഒറ്റപ്പെട്ട', 'severity': 'CAUTION'},
    {'keyword': 'ഭയം', 'severity': 'CAUTION'},
  ];

  static const Duration _sessionIdleTimeout = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAI();
    _initializeSpeech();
    _initializeTts();
    _loadUserProfile();
    _loadPersistentMemory();
    _loadCaregiverNotes();
    if (ConnectivityService().isOnline) {
      _syncPendingMemory();
    }
    _connectivitySub = ConnectivityService().onlineStream.listen((online) {
      if (online) {
        _syncPendingMemory();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _finalizeChatSession();
    }
  }

  void _initializeAI() {
    _firebaseAI = FirebaseAI.vertexAI(auth: FirebaseAuth.instance);
    _model = _firebaseAI.generativeModel(model: 'gemini-2.5-flash');
  }



  String _detectLanguageLocale(String text) {
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text) || _isManglish(text)) return 'ml-IN';
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi-IN'; // Devanagari (Hindi/Marathi)
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta-IN'; // Tamil
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kn-IN'; // Kannada
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'te-IN'; // Telugu
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(text)) return 'bn-IN'; // Bengali
    if (RegExp(r'[\u0A00-\u0A7F]').hasMatch(text)) return 'pa-IN'; // Gurmukhi (Punjabi)
    if (RegExp(r'[\u0A80-\u0AFF]').hasMatch(text)) return 'gu-IN'; // Gujarati
    
    // Default fallback
    return 'en-US';
  }

  Future<void> _applyLanguagePreference(
    String preference, {
    bool persist = false,
  }) async {
    String normalized = _supportedLanguages.containsKey(preference) 
        ? preference 
        : 'auto';

    setState(() {
      _languagePreference = normalized;
      _detectedLanguage = normalized == 'auto' ? _detectedLanguage : normalized;
    });

    if (persist) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'preferredLanguage': normalized,
        }, SetOptions(merge: true));
      }
    }
  }

  void _updateAutoLanguageFromMessage(String messageText) {
    final detected = _detectLanguageLocale(messageText);
    _languageHistory.add(detected);
    if (_languageHistory.length > 5) {
      _languageHistory.removeAt(0);
    }

    if (_languagePreference != 'auto') return;

    final map = <String, int>{};
    for (var lang in _languageHistory) {
      map[lang] = (map[lang] ?? 0) + 1;
    }
    
    var mostCommon = 'en-US';
    var maxCount = 0;
    map.forEach((lang, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommon = lang;
      }
    });

    if (maxCount >= 3 && mostCommon != _detectedLanguage) {
      setState(() {
        _detectedLanguage = mostCommon;
      });
    }
  }

  Future<void> _showLanguagePicker() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voice Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: RadioGroup<String>(
            groupValue: _languagePreference,
            onChanged: (value) async {
              Navigator.pop(context);
              await _applyLanguagePreference(
                value ?? 'auto',
                persist: true,
              );
            },
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _supportedLanguages.length,
              itemBuilder: (context, index) {
                final key = _supportedLanguages.keys.elementAt(index);
                final name = _supportedLanguages[key]!;
                return RadioListTile<String>(
                  title: Text(name),
                  value: key,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // LOAD USER PROFILE
  // ============================================
  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (docSnapshot.exists) {
          final pref = (docSnapshot.data()?['preferredLanguage'] ?? 'auto').toString();
          setState(() {
            _userProfile = docSnapshot.data();
            _isLoadingProfile = false;
          });
          await _applyLanguagePreference(pref, persist: false);
        } else {
          setState(() {
            _isLoadingProfile = false;
          });
        }
      }
    } catch (e) {
      print('Error loading user profile: $e');
      setState(() {
        _isLoadingProfile = false;
      });
    }
    _checkAndSendInitialMessage();
  }

  // ============================================
  // LOAD PERSISTENT MEMORY
  // ============================================
  Future<void> _loadPersistentMemory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get key facts
        final getKeyFactsCallable = _functions.httpsCallable('getAllKeyFacts');
        final factsResult = await getKeyFactsCallable.call();

        // Get recent memories
        final getMemoriesCallable = _functions.httpsCallable(
          'getRelevantMemories',
        );
        final memoriesResult = await getMemoriesCallable.call({
          'currentMessage': 'startup',
          'limit': 5,
        });

        setState(() {
          _persistentMemory = factsResult.data['keyFacts'] ?? {};
          _recentMemories = List<Map<String, dynamic>>.from(
            memoriesResult.data['memories'] ?? [],
          );
          _isLoadingMemory = false;
        });
      }
    } catch (e) {
      print('Error loading persistent memory: $e');
      setState(() {
        _isLoadingMemory = false;
      });
    }
    _checkAndSendInitialMessage();
  }

  Future<void> _loadCaregiverNotes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final notesSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('caregiver_notes')
            .where('active', isEqualTo: true)
            .get();

        final notes = notesSnap.docs
            .map((d) => (d.data()['text'] ?? '').toString().trim())
            .where((t) => t.isNotEmpty)
            .toList();

        setState(() {
          _caregiverNotes = notes;
          _isLoadingCaregiverNotes = false;
        });
      } else {
        setState(() {
          _caregiverNotes = [];
          _isLoadingCaregiverNotes = false;
        });
      }
    } catch (e) {
      print('Error loading caregiver notes: $e');
      setState(() {
        _caregiverNotes = [];
        _isLoadingCaregiverNotes = false;
      });
    }

    _checkAndSendInitialMessage();
  }

  // ============================================
  // CHECK AND SEND INITIAL MESSAGE
  // ============================================
  void _checkAndSendInitialMessage() {
    if (!_initialMessageSent &&
        !_isLoadingProfile &&
        !_isLoadingMemory &&
        !_isLoadingCaregiverNotes) {
      _sendInitialMessage();
    }
  }

  // ============================================
  // BUILD USER CONTEXT WITH MEMORY
  // ============================================
  String _buildUserContext() {
    StringBuffer context = StringBuffer();

    context.writeln("\n\n### USER PROFILE INFORMATION:");
    context.writeln(
      "Use this information to personalize your interactions with the user.\n",
    );

    // Add profile information
    if (_userProfile != null) {
      if (_userProfile!['name'] != null) {
        context.writeln("- User's Name: ${_userProfile!['name']}");
      }
      if (_userProfile!['age'] != null) {
        context.writeln("- Age: ${_userProfile!['age']}");
      }
      if (_userProfile!['interests'] != null) {
        context.writeln("- Interests: ${_userProfile!['interests']}");
      }
      if (_userProfile!['hobbies'] != null) {
        context.writeln("- Hobbies: ${_userProfile!['hobbies']}");
      }
      if (_userProfile!['skills'] != null) {
        context.writeln("- Skills: ${_userProfile!['skills']}");
      }
    }

    // Add persistent memory facts
    if (_persistentMemory != null && _persistentMemory!.isNotEmpty) {
      context.writeln("\n### LEARNED FACTS FROM PREVIOUS CONVERSATIONS:");
      _persistentMemory!.forEach((key, value) {
        context.writeln("- $key: $value");
      });
    }

    // Add recent conversation context
    if (_recentMemories.isNotEmpty) {
      context.writeln("\n### RECENT CONVERSATION CONTEXT:");
      for (int i = 0; i < _recentMemories.take(3).length; i++) {
        final memory = _recentMemories[i];
        context.writeln("- User said: ${memory['userMessage']}");
        if (memory['keyFacts'] != null && memory['keyFacts'].isNotEmpty) {
          context.writeln("  Key points: ${memory['keyFacts'].join(', ')}");
        }
      }
    }

    if (_caregiverNotes.isNotEmpty) {
      context.writeln(
        "\n### CAREGIVER NOTES (trusted context about this user):",
      );
      for (final note in _caregiverNotes) {
        context.writeln("- $note");
      }
    }

    context.writeln(
      "\nUse all this context to provide deeply personalized responses.",
    );
    return context.toString();
  }

  // ============================================
  // STORE CONVERSATION TO MEMORY & KEY FACTS
  // ============================================
  bool _isManglish(String text) {
    final lower = text.toLowerCase();

    const manglishKeywords = [
      'ennu',
      'ente',
      'enikku',
      'njan',
      'ningal',
      'anu',
      'illa',
      'undo',
      'sukham',
      'vishamam',
      'thonnunnu',
      'eduthu',
      'kazhicho',
      'kazhichu',
      'urakkam',
      'marunnu',
      'vedana',
    ];

    return manglishKeywords.any((word) => lower.contains(word));
  }

  String _detectMood(String message) {
    final text = message.toLowerCase();

    if (text.contains('anxious') ||
        text.contains('worried') ||
        text.contains('panic') ||
        text.contains('fear') ||
        text.contains('nervous') ||
        text.contains('ഭയം') ||
        text.contains('ആശങ്ക')) {
      return 'anxious';
    }

    if (text.contains('sad') ||
        text.contains('lonely') ||
        text.contains('low') ||
        text.contains('depressed') ||
        text.contains('down') ||
        text.contains('വിഷമം') ||
        text.contains('ഒറ്റപ്പെട') ||
        text.contains('ദുഃഖ') ||
        text.contains('സങ്കട')) {
      return 'sad';
    }

    if (text.contains('tired') ||
        text.contains('exhausted') ||
        text.contains('weak') ||
        text.contains('sleepy') ||
        text.contains('fatigue') ||
        text.contains('ക്ഷീണം') ||
        text.contains('തളർച്ച') ||
        text.contains('ക്ലാന്ത')) {
      return 'tired';
    }

    if (text.contains('calm') ||
        text.contains('peaceful') ||
        text.contains('relaxed') ||
        text.contains('okay') ||
        text.contains('settled') ||
        text.contains('ശാന്ത') ||
        text.contains('സമാധാനം')) {
      return 'calm';
    }

    if (text.contains('happy') ||
        text.contains('good') ||
        text.contains('fine') ||
        text.contains('great') ||
        text.contains('better') ||
        text.contains('glad') ||
        text.contains('സന്തോഷ') ||
        text.contains('നല്ല')) {
      return 'happy';
    }

    return 'calm';
  }

  String _hourBucketId(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    return '${y}${m}${d}_$h';
  }

  Future<void> _storeConversationMemory(
    String userMessage,
    String aiResponse,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final firestore = FirebaseFirestore.instance;

      final mood = _detectMood(userMessage);
      await firestore.collection('users').doc(user.uid).set({
        'lastMood': mood,
        'lastMoodAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final now = DateTime.now();
      final moodLogId = _hourBucketId(now);
      final moodLogRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('mood_logs')
          .doc(moodLogId);
      final moodLogSnap = await moodLogRef.get();
      if (!moodLogSnap.exists) {
        final snippet =
            userMessage.length > 60 ? userMessage.substring(0, 60) : userMessage;
        await moodLogRef.set({
          'mood': mood,
          'messageSnippet': snippet,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: false));
      }

      // Extract key facts from the conversation
      List<String> keyFacts = _extractKeyFacts(userMessage, aiResponse);

      // 1. Store the memory entry
      final storeMemoryCallable = _functions.httpsCallable(
        'storeConversationMemory',
      );
      try {
        await storeMemoryCallable.call({
          'message': userMessage,
          'response': aiResponse,
          'keyFacts': keyFacts,
        });
      } catch (e) {
        await _queuePendingMemorySync(userMessage, aiResponse);
      }

      // 2. Store individual key facts to Firestore
      if (keyFacts.isNotEmpty) {
        final batch = firestore.batch();

        for (String fact in keyFacts) {
          // Parse fact to extract key and value (assumes format "key: value")
          final parts = fact.split(':');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join(':').trim();

            // Store in key_facts collection
            final factRef = firestore
                .collection('users')
                .doc(user.uid)
                .collection('key_facts')
                .doc(key);

            batch.set(factRef, {
              'value': value,
              'updatedAt': FieldValue.serverTimestamp(),
              'factType': key,
            }, SetOptions(merge: true));
          }
        }

        await batch.commit();
      }

      // Reload memory for future context
      await _loadPersistentMemory();
    } catch (e) {
      print('Error storing memory: $e');
    }
  }

  // ============================================
  // EXTRACT KEY FACTS FROM CONVERSATION
  // ============================================
  List<String> _extractKeyFacts(String userMessage, String aiResponse) {
    List<String> facts = [];

    // Simple pattern matching for key facts
    final patterns = [
      RegExp(r"my (.*?) is (\w+)", caseSensitive: false),
      RegExp(r"i (love|like|enjoy|hate|dislike) (\w+)", caseSensitive: false),
      RegExp(r"my (\w+) is named (\w+)", caseSensitive: false),
      RegExp(r"i have a (\w+) named (\w+)", caseSensitive: false),
      RegExp(r"(.*?) is my (.*)", caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final matches = pattern.allMatches(userMessage);
      for (var match in matches) {
        if (match.groupCount >= 2) {
          facts.add("${match.group(1)}: ${match.group(2)}");
        }
      }
    }

    return facts;
  }

  Future<void> _initializeSpeech() async {
    _speech = stt.SpeechToText();
    await _speech.initialize(
      onError: (error) => print('Speech recognition error: $error'),
      onStatus: (status) => print('Speech recognition status: $status'),
    );
  }

  Future<void> _initializeTts() async {
    _flutterTts = FlutterTts();

    await _flutterTts.setSpeechRate(0.55); // Set to 0.55 for a slightly faster but still clear speed
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.1); // Slightly higher pitch for a gentler voice

    _flutterTts.setStartHandler(() {
      setState(() => _isSpeaking = true);
    });

    _flutterTts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
  }

  void _sendInitialMessage() {
    String greeting =
        "Hello! I am Mitra, your personal companion. I'm here to chat, remind you of things, and keep you company.";

    if (widget.wellnessMode) {
      final name = (_userProfile?['name'] ?? '').toString();
      greeting = name.isEmpty
          ? 'Good morning! How are you feeling today on a scale of 1–10?'
          : 'Good morning $name! How are you feeling today on a scale of 1–10?';
    }

    if (_userProfile != null && _userProfile!['name'] != null) {
      greeting =
          "Hello ${_userProfile!['name']}! I am Mitra, your personal companion. I'm here to chat, remind you of things, and keep you company.";
    }

    final ChatMessage introMessage = ChatMessage(
      user: _aiUser,
      createdAt: DateTime.now(),
      text: greeting,
    );

    setState(() {
      _messages.insert(0, introMessage);
      _initialMessageSent = true;
    });

    if (_speechEnabled) {
      _speak(introMessage.text);
    }
  }

  Future<void> _speak(String text) async {
    if (!_speechEnabled) return;

    String targetLocale = 'en-US';
    if (_languagePreference != 'auto') {
      targetLocale = _languagePreference;
    } else {
      targetLocale = _detectLanguageLocale(text);
    }

    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        List<Map<String, String>> localeVoices = [];
        for (var v in voices) {
          if (v is Map) {
            final loc = v['locale']?.toString() ?? '';
            // Match the language code (e.g., 'en' or 'ml' or 'hi')
            if (loc.toLowerCase().startsWith(targetLocale.split('-')[0].toLowerCase())) {
              localeVoices.add({
                'name': v['name']?.toString() ?? '',
                'locale': loc,
              });
            }
          }
        }

        if (localeVoices.isNotEmpty) {
          // Attempt to find a distinctly female-named voice
          var selectedVoice = localeVoices.firstWhere(
            (v) => v['name']!.toLowerCase().contains('female') || v['name']!.toLowerCase().contains('-f-'),
            orElse: () => localeVoices.first,
          );
          
          await _flutterTts.setVoice({"name": selectedVoice['name']!, "locale": selectedVoice['locale']!});
        } else {
          await _flutterTts.setLanguage(targetLocale);
        }
      } else {
        await _flutterTts.setLanguage(targetLocale);
      }
    } catch (e) {
      await _flutterTts.setLanguage(targetLocale);
    }

    await _flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
    });
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        final prefLocale = _languagePreference == 'auto' 
            ? _detectedLanguage 
            : _languagePreference;
        final localeId = prefLocale.replaceAll('-', '_');
        _speech.listen(
          onResult: (result) {
            setState(() {
              _lastWords = result.recognizedWords;
              _controller.text = _lastWords;
            });
          },
          localeId: localeId,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          listenOptions: stt.SpeechListenOptions(
            partialResults: true,
            cancelOnError: true,
            listenMode: stt.ListenMode.confirmation,
          ),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();

      if (_controller.text.isNotEmpty) {
        _handleSend();
      }
    }
  }

  Future<void> _handleSend([String? text]) async {
    final messageText = text ?? _controller.text;
    if (messageText.trim().isEmpty) return;

    if (!ConnectivityService().isOnline) {
      final offlineMessage = ChatMessage(
        user: _aiUser,
        createdAt: DateTime.now(),
        text: "I'm not connected to the internet right now. I'll be back when you're online.",
      );
      setState(() {
        _messages.insert(0, offlineMessage);
      });
      return;
    }

    _updateAutoLanguageFromMessage(messageText);

    final now = DateTime.now();
    if (_lastMessageAt != null &&
        now.difference(_lastMessageAt!) > _sessionIdleTimeout &&
        _sessionMessages.isNotEmpty) {
      await _finalizeChatSession(sessionEnd: _lastMessageAt!);
    }

    await _stopSpeaking();

    final userMessage = ChatMessage(
      user: _currentUser,
      createdAt: DateTime.now(),
      text: messageText,
    );

    setState(() {
      _messages.insert(0, userMessage);
      _controller.clear();
    });

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null) {
      FirebaseFirestore.instance.collection('users').doc(authUser.uid).set({
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        print('Failed to update lastActive: $e');
      });
    }

    _sessionMessages.add({'role': 'user', 'text': messageText});
    _lastMessageAt = DateTime.now();

    _checkForDistress(messageText);

    if (widget.wellnessMode) {
      await _storeWellnessScoreIfPresent(messageText);
    }

    _scrollToTop();

    try {
      final String completePrompt = _systemPrompt + _buildUserContext();

      final response = await _model.generateContent([
        Content.text(completePrompt),
        Content.text(
          "User message: $messageText\nReply warmly and shortly in the same general language as the user (e.g. Hindi if they speak Hindi, Tamil if they speak Tamil, Spanish if they speak Spanish, etc.), like a caring friend.",
        ),
      ]);

      final aiText = response.text ?? "Warning: No response from Mitra.";

      final aiMessage = ChatMessage(
        user: _aiUser,
        createdAt: DateTime.now(),
        text: aiText,
      );

      setState(() {
        _messages.insert(0, aiMessage);
      });
      _sessionMessages.add({'role': 'ai', 'text': aiText});
      _lastMessageAt = DateTime.now();

      _scrollToTop();
      
      // FIRE TTS IMMEDIATELY TO AVOID LATENCY
      // Do not await it so it starts talking right away
      _speak(aiText);

      // Store the conversation to persistent memory with key facts in the background
      await _storeConversationMemory(messageText, aiText);
    } catch (e) {
      final errorMessage = ChatMessage(
        user: _aiUser,
        createdAt: DateTime.now(),
        text: "Error: $e",
      );
      setState(() {
        _messages.insert(0, errorMessage);
      });

      _scrollToTop();
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finalizeChatSession();
    _connectivitySub?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _queuePendingMemorySync(String message, String response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pending_memory_sync');
      final list = raw == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(jsonDecode(raw));

      list.add({
        'message': message,
        'response': response,
        'timestamp': DateTime.now().toIso8601String(),
      });

      await prefs.setString('pending_memory_sync', jsonEncode(list));
    } catch (e) {
      print('Failed to queue pending memory sync: $e');
    }
  }

  Future<void> _syncPendingMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pending_memory_sync');
      if (raw == null || raw.isEmpty) return;

      final pending = List<Map<String, dynamic>>.from(jsonDecode(raw));
      if (pending.isEmpty) return;

      final callable = _functions.httpsCallable('storeConversationMemory');
      final remaining = <Map<String, dynamic>>[];

      for (final item in pending) {
        try {
          final message = (item['message'] ?? '').toString();
          final response = (item['response'] ?? '').toString();
          final keyFacts = _extractKeyFacts(message, response);

          await callable.call({
            'message': message,
            'response': response,
            'keyFacts': keyFacts,
          });
        } catch (_) {
          remaining.add(item);
        }
      }

      await prefs.setString('pending_memory_sync', jsonEncode(remaining));
    } catch (e) {
      print('Failed syncing pending memory: $e');
    }
  }

  Future<void> _finalizeChatSession({DateTime? sessionEnd}) async {
    if (_isGeneratingSummary || _sessionMessages.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isGeneratingSummary = true;
    final endTime = sessionEnd ?? DateTime.now();

    try {
      final callable = _functions.httpsCallable('generateChatSummary');
      await callable.call({
        'uid': user.uid,
        'sessionStart': _sessionStartTime.toIso8601String(),
        'sessionEnd': endTime.toIso8601String(),
        'messages': _sessionMessages,
      });

      _sessionMessages.clear();
      _sessionStartTime = DateTime.now();
      _lastMessageAt = null;
    } catch (e) {
      print('Error generating chat summary: $e');
    } finally {
      _isGeneratingSummary = false;
    }
  }

  void _checkForDistress(String message) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final normalized = message.toLowerCase();
    for (final item in _distressKeywords) {
      final keyword = item['keyword'] ?? '';
      final severity = item['severity'] ?? 'CAUTION';
      if (keyword.isEmpty) continue;

      final pattern = RegExp(
        RegExp.escape(keyword.toLowerCase()),
        caseSensitive: false,
      );

      if (pattern.hasMatch(normalized)) {
        final snippet = message.length > 100 ? message.substring(0, 100) : message;
        unawaited(() async {
          try {
            await _functions.httpsCallable('triggerDistressAlert').call({
              'uid': user.uid,
              'keyword': keyword,
              'severity': severity,
              'messageSnippet': snippet,
            });
          } catch (e) {
            print('Distress alert trigger failed: $e');
          }
        }());
        return;
      }
    }
  }

  Future<void> _storeWellnessScoreIfPresent(String messageText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final match = RegExp(r'^\s*([1-9]|10)\s*$').firstMatch(messageText);
    if (match == null) return;

    final score = int.tryParse(match.group(1) ?? '');
    if (score == null) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userDoc.collection('wellness_logs').doc(today).set({
        'score': score,
        'message': messageText,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await userDoc.set({
        'lastWellnessScore': score,
        'lastWellnessDate': today,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Failed storing wellness score: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Text(
              _languagePreference == 'auto'
                  ? 'AUTO'
                  : ((_languagePreference == 'ml-IN') ? 'ML' : 'EN'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            tooltip: 'Language',
            onPressed: _showLanguagePicker,
          ),
          Row(
            children: [
              const Icon(Icons.volume_up, size: 20),
              Switch(
                value: _speechEnabled,
                onChanged: (value) {
                  setState(() {
                    _speechEnabled = value;
                  });
                  if (!value) {
                    _stopSpeaking();
                  }
                },
                activeThumbColor: Colors.teal,
              ),
            ],
          ),
          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopSpeaking,
              tooltip: 'Stop speaking',
            ),
        ],
      ),
        body: (_isLoadingProfile || _isLoadingMemory || _isLoadingCaregiverNotes)
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: DashChat(
                    currentUser: _currentUser,
                    messages: _messages,
                    inputOptions: InputOptions(
                      inputDisabled: true,
                      alwaysShowSend: false,
                      inputDecoration: const InputDecoration.collapsed(
                        hintText: '',
                      ),
                    ),
                    messageOptions: const MessageOptions(showTime: true),
                    onSend: (_) {},
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: _isListening
                            ? Colors.red
                            : Colors.blue,
                        child: IconButton(
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                          ),
                          onPressed: _listen,
                          tooltip: _isListening
                              ? 'Stop listening'
                              : 'Start voice input',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: "Type a message...",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onSubmitted: (_) => _handleSend(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: Colors.teal,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _handleSend,
                          tooltip: 'Send message',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
