import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _taskName = 'dailyClipping';
final _notifications = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _taskName) {
      final prefs = await SharedPreferences.getInstance();
      final terms = prefs.getStringList('clip_terms') ?? <String>[];
      var totalNew = 0;
      for (final term in terms) {
        final items = await NewsApi.search(term, date: '24h');
        final key = 'seen_${term.toLowerCase()}';
        final seen = (prefs.getStringList(key) ?? <String>[]).toSet();
        final fresh = items.where((e) => !seen.contains(e.id)).toList();
        totalNew += fresh.length;
        seen.addAll(items.map((e) => e.id));
        await prefs.setStringList(key, seen.take(500).toList());
      }
      if (totalNew > 0) {
        await _notifications.show(
          1001,
          'ClipWatch',
          '$totalNew novas referências encontradas no clipping.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'clipping_alerts',
              'Alertas de clipping',
              channelDescription: 'Novas referências encontradas nos nomes monitorizados',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    }
    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifications.initialize(const InitializationSettings(android: initAndroid));
  final androidImpl = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'clipwatch-daily-task',
    _taskName,
    frequency: const Duration(hours: 24),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
  runApp(const ClipWatchApp());
}

class ClipWatchApp extends StatelessWidget {
  const ClipWatchApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ClipWatch',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16213E)),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      home: const HomePage(),
    );
  }
}

class NewsItem {
  final String id;
  final String title;
  final String description;
  final String url;
  final String source;
  final String publishedAt;
  NewsItem({required this.id, required this.title, required this.description, required this.url, required this.source, required this.publishedAt});
  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
    id: (j['id'] ?? j['url'] ?? '').toString(),
    title: (j['title'] ?? 'Sem título').toString(),
    description: (j['description'] ?? '').toString(),
    url: (j['url'] ?? '').toString(),
    source: (j['sitename'] ?? j['host'] ?? 'Fonte').toString(),
    publishedAt: (j['published_at'] ?? '').toString(),
  );
}

class NewsApi {
  static Future<List<NewsItem>> search(String query, {String date = '7d'}) async {
    final uri = Uri.https('freenewsapi.ai', '/v1/search', {
      'q': query,
      'country': 'PT',
      'lang': 'pt',
      'date': date,
      'sort': 'date',
      'size': '50',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Erro ${res.statusCode} na pesquisa');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ((data['results'] as List?) ?? const [])
        .map((e) => NewsItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  List<String> _terms = [];
  String? _selected;
  List<NewsItem> _news = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _terms = prefs.getStringList('clip_terms') ?? []);
  }

  Future<void> _saveTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('clip_terms', _terms);
  }

  Future<void> _addTerm() async {
    final t = _controller.text.trim();
    if (t.isEmpty || _terms.contains(t)) return;
    setState(() {
      _terms.add(t);
      _controller.clear();
    });
    await _saveTerms();
    await _openTerm(t);
  }

  Future<void> _removeTerm(String t) async {
    setState(() {
      _terms.remove(t);
      if (_selected == t) {
        _selected = null;
        _news = [];
      }
    });
    await _saveTerms();
  }

  Future<void> _openTerm(String t) async {
    setState(() {
      _selected = t;
      _loading = true;
      _error = null;
    });
    try {
      final result = await NewsApi.search(t);
      if (!mounted) return;
      setState(() => _news = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClipWatch', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: _selected == null ? null : () => _openTerm(_selected!), icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addTerm(),
                          decoration: const InputDecoration(
                            labelText: 'Nome, empresa ou expressão',
                            hintText: 'Ex.: Miguel Reis',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(onPressed: _addTerm, icon: const Icon(Icons.add), label: const Text('Monitorizar')),
                    ],
                  ),
                ),
              ),
            ),
            if (_terms.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _terms.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final t = _terms[i];
                    return InputChip(
                      selected: _selected == t,
                      label: Text(t),
                      avatar: const Icon(Icons.radar, size: 18),
                      onPressed: () => _openTerm(t),
                      onDeleted: () => _removeTerm(t),
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_selected == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Adicione um nome. O ClipWatch guardará a monitorização e fará clipping diário em background.', textAlign: TextAlign.center)));
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    if (_news.isEmpty) return Center(child: Text('Sem resultados recentes para “$_selected”.'));
    return RefreshIndicator(
      onRefresh: () => _openTerm(_selected!),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _news.length,
        itemBuilder: (context, i) {
          final n = _news[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${n.source} • ${_prettyDate(n.publishedAt)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (n.description.isNotEmpty) ...[const SizedBox(height: 6), Text(n.description, maxLines: 3, overflow: TextOverflow.ellipsis)],
                ]),
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                final uri = Uri.tryParse(n.url);
                if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          );
        },
      ),
    );
  }

  String _prettyDate(String raw) {
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return 'data desconhecida';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
