import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static Storage? _instance;
  static Future<Storage>? _pendingInit;
  late final SharedPreferences _prefs;

  Storage._();

  static Future<Storage> get instance async {
    if (_instance != null) return _instance!;
    if (_pendingInit != null) return _pendingInit!;
    _pendingInit = _doInit();
    final storage = await _pendingInit!;
    _pendingInit = null;
    return storage;
  }

  static Future<Storage> _doInit() async {
    final storage = Storage._();
    storage._prefs = await SharedPreferences.getInstance();
    _instance = storage;
    return storage;
  }

  // -- Conversations --

  List<Map<String, dynamic>> getAllConversations() {
    final raw = _prefs.getString('conversations');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveAllConversations(List<Map<String, dynamic>> list) async {
    await _prefs.setString('conversations', jsonEncode(list));
  }

  Map<String, dynamic>? getConversation(String id) {
    final all = getAllConversations();
    try {
      return all.firstWhere((c) => c['id'] == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> insertConversation(Map<String, dynamic> conv) async {
    final all = getAllConversations();
    final idx = all.indexWhere((c) => c['id'] == conv['id']);
    if (idx >= 0) {
      all[idx] = conv;
    } else {
      all.add(conv);
    }
    await saveAllConversations(all);
  }

  Future<void> updateConversation(Map<String, dynamic> conv) async {
    final all = getAllConversations();
    final idx = all.indexWhere((c) => c['id'] == conv['id']);
    if (idx >= 0) {
      all[idx] = conv;
      await saveAllConversations(all);
    }
  }

  Future<void> deleteConversation(String id) async {
    final all = getAllConversations();
    all.removeWhere((c) => c['id'] == id);
    await saveAllConversations(all);
    await _prefs.remove('messages_$id');
  }

  // -- Messages --

  List<Map<String, dynamic>> getMessages(String conversationId) {
    final raw = _prefs.getString('messages_$conversationId');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveMessages(
      String conversationId, List<Map<String, dynamic>> list) async {
    await _prefs.setString('messages_$conversationId', jsonEncode(list));
  }

  Future<void> insertMessage(Map<String, dynamic> msg) async {
    final convId = msg['conversation_id'] as String;
    final all = getMessages(convId);
    final idx = all.indexWhere((m) => m['id'] == msg['id']);
    if (idx >= 0) {
      all[idx] = msg;
    } else {
      all.add(msg);
    }
    await saveMessages(convId, all);
  }

  Future<void> updateMessage(String id, String conversationId,
      Map<String, dynamic> data) async {
    final all = getMessages(conversationId);
    final idx = all.indexWhere((m) => m['id'] == id);
    if (idx >= 0) {
      all[idx] = {...all[idx], ...data};
      await saveMessages(conversationId, all);
    }
  }

  Future<void> deleteMessages(String conversationId) async {
    await _prefs.remove('messages_$conversationId');
  }

  // -- Expert Panels --

  List<Map<String, dynamic>> getAllExpertPanels() {
    final raw = _prefs.getString('expert_panels');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveAllExpertPanels(List<Map<String, dynamic>> list) async {
    await _prefs.setString('expert_panels', jsonEncode(list));
  }

  Future<void> insertExpertPanel(Map<String, dynamic> panel) async {
    final all = getAllExpertPanels();
    final idx = all.indexWhere((p) => p['id'] == panel['id']);
    if (idx >= 0) {
      all[idx] = panel;
    } else {
      all.add(panel);
    }
    await saveAllExpertPanels(all);
  }

  Future<void> deleteExpertPanel(String id) async {
    final all = getAllExpertPanels();
    all.removeWhere((p) => p['id'] == id);
    await saveAllExpertPanels(all);
  }

  // -- Personas --

  List<Map<String, dynamic>> getAllPersonas() {
    final raw = _prefs.getString('personas');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveAllPersonas(List<Map<String, dynamic>> list) async {
    await _prefs.setString('personas', jsonEncode(list));
  }

  Future<void> insertPersona(Map<String, dynamic> persona) async {
    final all = getAllPersonas();
    final idx = all.indexWhere((p) => p['id'] == persona['id']);
    if (idx >= 0) {
      all[idx] = persona;
    } else {
      all.add(persona);
    }
    await saveAllPersonas(all);
  }

  Future<void> deletePersona(String id) async {
    final all = getAllPersonas();
    all.removeWhere((p) => p['id'] == id);
    await saveAllPersonas(all);
  }
}
