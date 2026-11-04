import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF000000),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const LeakBotOledApp());
}

class LeakBotOledApp extends StatelessWidget {
  const LeakBotOledApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LeakBot Apex OLED',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        cardColor: const Color(0xFF101018),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF101018),
          error: Color(0xFFEF4444),
        ),
      ),
      home: const LeakBotHomeScreen(),
    );
  }
}

class LeakBotHomeScreen extends StatefulWidget {
  const LeakBotHomeScreen({super.key});

  @override
  State<LeakBotHomeScreen> createState() => _LeakBotHomeScreenState();
}

class _LeakBotHomeScreenState extends State<LeakBotHomeScreen> {
  static const MethodChannel _shareChannel = MethodChannel('leakbot.oled/share');

  String _hostUrl = 'http://192.168.1.100:5000';
  int _selectedIndex = 0;
  bool _isOnline = false;
  bool _wasOnline = false;

  Map<String, dynamic> _statusData = {};
  List<dynamic> _searchResults = [];
  String _lyricsText = 'Tap "Fetch Current Lyrics" to load Genius lyrics.';
  double _volumeValue = 100.0;

  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _songCtrl = TextEditingController();
  final TextEditingController _seekCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initSettingsAndBridge();
  }

  Future<void> _initSettingsAndBridge() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostUrl = prefs.getString('leakbot_host_url') ?? 'http://192.168.1.100:5000';
      _hostCtrl.text = _hostUrl;
    });

    // Listen for Android Share Sheet intents (YouTube, Spotify, SoundCloud, Apple Music)
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText' && call.arguments != null) {
        final String sharedText = call.arguments.toString().trim();
        if (sharedText.isNotEmpty) {
          _songCtrl.text = sharedText;
          await _queueOrPlaySong(sharedText, playNow: false);
        }
      }
    });

    try {
      final String? initialShared = await _shareChannel.invokeMethod<String>('getInitialSharedText');
      if (initialShared != null && initialShared.trim().isNotEmpty) {
        _songCtrl.text = initialShared.trim();
        await _queueOrPlaySong(initialShared.trim(), playNow: false);
      }
    } catch (_) {}

    await _pollBotStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollBotStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _hostCtrl.dispose();
    _songCtrl.dispose();
    _seekCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveHostUrl(String newUrl) async {
    String clean = newUrl.trim();
    if (!clean.startsWith('http')) clean = 'http://$clean';
    if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('leakbot_host_url', clean);
    setState(() => _hostUrl = clean);
    _pollBotStatus();
  }

  Future<void> _pollBotStatus() async {
    try {
      final resp = await http
          .get(Uri.parse('$_hostUrl/api/status'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final bool nowOnline = data['status'] == 'online';

        if (nowOnline && !_wasOnline && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🟢 LeakBot is ONLINE (Ryzen 9 7900X3D)'),
              backgroundColor: Color(0xFF059669),
              duration: Duration(seconds: 2),
            ),
          );
        }
        setState(() {
          _isOnline = nowOnline;
          _wasOnline = nowOnline;
          _statusData = data;
          _volumeValue = (data['volume'] ?? 100).toDouble();
        });
      } else {
        _handleOfflineTransition();
      }
    } catch (_) {
      _handleOfflineTransition();
    }
  }

  void _handleOfflineTransition() {
    if (_wasOnline && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔴 LeakBot went OFFLINE! Waiting for reconnection...'),
          backgroundColor: Color(0xFFDC2626),
          duration: Duration(seconds: 4),
        ),
      );
    }
    if (mounted) {
      setState(() {
        _isOnline = false;
        _wasOnline = false;
      });
    }
  }

  Future<void> _queueOrPlaySong(String urlOrQuery, {bool playNow = false}) async {
    if (urlOrQuery.trim().isEmpty) return;
    try {
      final resp = await http.post(
        Uri.parse('$_hostUrl/api/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': urlOrQuery.trim(), 'play_now': playNow}),
      );
      final data = jsonDecode(resp.body);
      if (mounted) {
        if (data['success'] == true) {
          _songCtrl.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📥 Queued: ${data['title'] ?? urlOrQuery}'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _pollBotStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ ${data['error'] ?? 'Failed'}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Connection error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _sendControl(String action, [Map<String, dynamic>? extra]) async {
    try {
      await http.post(
        Uri.parse('$_hostUrl/api/control'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action, ...?extra}),
      );
      _pollBotStatus();
    } catch (_) {}
  }

  Future<void> _uploadAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'flac', 'ogg'],
    );
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final req = http.MultipartRequest('POST', Uri.parse('$_hostUrl/api/upload'));
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await req.send();
    if (streamed.statusCode == 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📤 Uploaded & Queued: ${result.files.single.name}')),
      );
      _pollBotStatus();
    }
  }

  Future<void> _runYoutubeSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    try {
      final resp = await http.post(
        Uri.parse('$_hostUrl/api/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': q}),
      );
      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        setState(() => _searchResults = data['results'] ?? []);
      }
    } catch (_) {}
  }

  Future<void> _fetchLyrics([String? customQuery]) async {
    setState(() => _lyricsText = 'Fetching lyrics from Genius...');
    try {
      final uri = Uri.parse('$_hostUrl/api/lyrics').replace(
        queryParameters: customQuery != null && customQuery.isNotEmpty ? {'query': customQuery} : null,
      );
      final resp = await http.get(uri);
      final data = jsonDecode(resp.body);
      setState(() {
        if (data['success'] == true) {
          _lyricsText = '📖 ${data['title']}\n\n${data['lyrics']}';
        } else {
          _lyricsText = data['error'] ?? 'Could not find lyrics.';
        }
      });
    } catch (e) {
      setState(() => _lyricsText = 'Error connecting to LeakBot: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nowPlaying = _statusData['now_playing'] as Map<String, dynamic>?;
    final queueList = (_statusData['queue'] as List<dynamic>?) ?? [];
    final historyList = (_statusData['history'] as List<dynamic>?) ?? [];
    final loopMode = (_statusData['loop_mode'] ?? 'Off').toString();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFF00FF88)),
            SizedBox(width: 6),
            Text('LEAKBOT // APEX OLED', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.8)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _isOnline ? const Color(0xFF062819) : const Color(0xFF2D0A0A),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: _isOnline ? const Color(0xFF00FF88) : const Color(0xFFEF4444)),
            ),
            child: Center(
              child: Text(
                _isOnline ? '● ONLINE' : '● OFFLINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _isOnline ? const Color(0xFF00FF88) : const Color(0xFFEF4444),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildPlayerTab(nowPlaying, loopMode),
          _buildQueueTab(queueList),
          _buildSearchAndLyricsTab(),
          _buildHistoryAndHostTab(historyList),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF050508),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF00FF88),
        unselectedItemColor: const Color(0xFF64748B),
        currentIndex: _selectedIndex,
        onTap: (idx) => setState(() => _selectedIndex = idx),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.headphones), label: 'Player'),
          BottomNavigationBarItem(icon: const Icon(Icons.queue_music), label: 'Queue (${queueList.length})'),
          const BottomNavigationBarItem(icon: Icon(Icons.lyrics), label: 'Search & Lyrics'),
          const BottomNavigationBarItem(icon: Icon(Icons.leaderboard), label: 'History & Host'),
        ],
      ),
    );
  }

  Widget _buildOledCard({required String title, required Widget child, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E2C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1.0)),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPlayerTab(Map<String, dynamic>? nowPlaying, String loopMode) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildOledCard(
          title: '📥 Share / Queue Music (YT, Spotify, Apple, SC)',
          child: Column(
            children: [
              TextField(
                controller: _songCtrl,
                decoration: InputDecoration(
                  hintText: 'Paste link or song title...',
                  filled: true,
                  fillColor: const Color(0xFF050508),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF88),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => _queueOrPlaySong(_songCtrl.text, playNow: false),
                      icon: const Icon(Icons.add),
                      label: const Text('Add to Queue', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => _queueOrPlaySong(_songCtrl.text, playNow: true),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play Now', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildOledCard(
          title: '🎧 Now Playing',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nowPlaying != null ? (nowPlaying['title'] ?? 'Unknown') : 'Nothing Playing',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'Server: ${_statusData['active_guild_name'] ?? '--'}  |  VC: ${_statusData['connected_vc_name'] ?? 'Disconnected'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _controlBtn(Icons.play_arrow, 'Pause/Play', () => _sendControl('pause_resume')),
                  _controlBtn(Icons.skip_next, 'Skip', () => _sendControl('skip')),
                  _controlBtn(Icons.repeat, 'Loop: $loopMode', () {
                    const modes = ['Off', 'Track', 'Queue'];
                    final next = modes[(modes.indexOf(loopMode) + 1) % 3];
                    _sendControl('loop', {'mode': next});
                  }),
                  _controlBtn(Icons.stop, 'Stop', () => _sendControl('stop'), isDanger: true),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('🔊 Vol ${_volumeValue.round()}%', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                  Expanded(
                    child: Slider(
                      value: _volumeValue.clamp(0.0, 100.0),
                      min: 0,
                      max: 100,
                      activeColor: const Color(0xFF00FF88),
                      onChanged: (v) => setState(() => _volumeValue = v),
                      onChangeEnd: (v) => _sendControl('volume', {'level': v.round()}),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _seekCtrl,
                      decoration: InputDecoration(
                        hintText: 'Seek (e.g. 1:30 or 90)',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF050508),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _sendControl('seek', {'timestamp': _seekCtrl.text}),
                    child: const Text('⏩ Seek'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _uploadAudioFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload MP3'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controlBtn(IconData icon, String label, VoidCallback onTap, {bool isDanger = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: isDanger ? const Color(0xFFEF4444) : Colors.white,
            side: BorderSide(color: isDanger ? const Color(0xFFEF4444) : const Color(0xFF262638)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: onTap,
          child: Column(
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueTab(List<dynamic> queueList) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildOledCard(
          title: '📜 Active Queue (${queueList.length} Tracks)',
          trailing: Row(
            children: [
              TextButton.icon(
                onPressed: () => _sendControl('shuffle'),
                icon: const Icon(Icons.shuffle, size: 16),
                label: const Text('Shuffle'),
              ),
              TextButton.icon(
                onPressed: () => _sendControl('clear'),
                icon: const Icon(Icons.delete_sweep, size: 16, color: Color(0xFFEF4444)),
                label: const Text('Clear', style: TextStyle(color: Color(0xFFEF4444))),
              ),
            ],
          ),
          child: queueList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('Queue is empty. Share a link from YouTube or Spotify!', style: TextStyle(color: Color(0xFF64748B)))),
                )
              : Column(
                  children: queueList.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07070B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1F1F2E)),
                      ),
                      child: Row(
                        children: [
                          Text('${idx + 1}.', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FF88))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item['title'] ?? 'Unknown Track',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.vertical_align_top, size: 18, color: Color(0xFF3B82F6)),
                            tooltip: 'Move to Top',
                            onPressed: () => _sendControl('move_top', {'index': idx}),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Color(0xFFEF4444)),
                            tooltip: 'Remove',
                            onPressed: () => _sendControl('remove_index', {'index': idx}),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchAndLyricsTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildOledCard(
          title: '🔍 Top-5 YouTube Interactive Search',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onSubmitted: (_) => _runYoutubeSearch(),
                      decoration: InputDecoration(
                        hintText: 'Search artist or track...',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF050508),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _runYoutubeSearch, child: const Text('Search')),
                ],
              ),
              const SizedBox(height: 10),
              ..._searchResults.map((r) {
                final item = r as Map<String, dynamic>;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text(item['uploader'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF88), foregroundColor: Colors.black),
                    onPressed: () => _queueOrPlaySong(item['url'] ?? item['title'], playNow: false),
                    child: const Text('Queue'),
                  ),
                );
              }),
            ],
          ),
        ),
        _buildOledCard(
          title: '📖 Genius Lyrics Viewer',
          trailing: TextButton(onPressed: () => _fetchLyrics(), child: const Text('Fetch Current Lyrics')),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF050508), borderRadius: BorderRadius.circular(12)),
            child: SelectableText(_lyricsText, style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryAndHostTab(List<dynamic> historyList) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildOledCard(
          title: '🔗 LeakBot PC Host Connection',
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hostCtrl,
                  decoration: InputDecoration(
                    hintText: 'http://192.168.1.XX:5000',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF050508),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _saveHostUrl(_hostCtrl.text),
                child: const Text('Connect'),
              ),
            ],
          ),
        ),
        _buildOledCard(
          title: '🖥️ AMD Ryzen 9 7900X3D Telemetry',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statBadge('CPU', '${_statusData['cpu_percent'] ?? '--'}%'),
              _statBadge('RAM', '${_statusData['ram_percent'] ?? '--'}%'),
              _statBadge('PING', '${_statusData['ping_ms'] ?? '--'}ms'),
              _statBadge('UPTIME', (_statusData['uptime'] ?? '--').toString().split(' ').first),
            ],
          ),
        ),
        _buildOledCard(
          title: '🏆 Full Host Playback History (${historyList.length} Songs)',
          child: historyList.isEmpty
              ? const Text('No playback history recorded yet.', style: TextStyle(color: Color(0xFF64748B)))
              : Column(
                  children: historyList.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final h = entry.value as Map<String, dynamic>;
                    final title = (h['title'] ?? 'Unknown').toString();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF1E293B),
                        child: Text('#${idx + 1}', style: const TextStyle(fontSize: 12, color: Color(0xFF00FF88), fontWeight: FontWeight.bold)),
                      ),
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('${h['plays'] ?? 1} plays', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00FF88)),
                        tooltip: 'Queue Again',
                        onPressed: () => _queueOrPlaySong(title, playNow: false),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _statBadge(String label, String val) {
    return Column(
      children: [
        Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF00FF88))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      ],
    );
  }
}
