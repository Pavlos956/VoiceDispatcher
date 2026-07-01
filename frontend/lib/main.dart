import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Background message handler — must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs on Android
  // Nothing extra needed — the system tray notification is shown automatically
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the background handler before the app starts
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  // Show the app shell immediately — Supabase + Firebase init inside AppLoader
  runApp(const MyApp());
}

// Accessed only after AppLoader confirms Supabase is ready.
SupabaseClient get supabase => Supabase.instance.client;

// ---------------------------------------------------------------------------
// Status constants — must match the values stored in Supabase
// ---------------------------------------------------------------------------
const String kStatusPending  = 'Pending';
const String kStatusBooked   = 'Booked';
const String kStatusWaiting  = 'To Be Called';
const String kStatusComplete = 'Complete';

const List<String> kTabLabels = [
  kStatusPending,
  kStatusBooked,
  kStatusWaiting,
  kStatusComplete,
];

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Technician Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AppLoader(),
    );
  }
}

// ---------------------------------------------------------------------------
// AppLoader — initialises Supabase asynchronously, shows a splash until ready
// ---------------------------------------------------------------------------
class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // Listen for sign-in / sign-out events and rebuild so the correct
  // screen (Login vs Dashboard) is shown without any explicit navigation.
  void _listenAuth() {
    supabase.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _init() async {
    try {
      // 1. Initialise Firebase
      await Firebase.initializeApp();

      // 2. Initialise Supabase
      await Supabase.initialize(
        url: 'https://oogjreozyrdcprechvnj.supabase.co',
        publishableKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vZ2pyZW96eXJkY3ByZWNodm5qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzNzY0NjUsImV4cCI6MjA5Nzk1MjQ2NX0.TtEUlyeE5L05H3NCCewPEpLrPSO7DmsMCiY_O9ng4fg',
      );

      // 3. Request notification permission (Android 13+ / iOS)
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // 4. Get this device's FCM token and save it to Supabase
      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);

      // 5. Refresh token if FCM rotates it
      messaging.onTokenRefresh.listen(_saveToken);

      // 6. Handle notifications that arrive while the app is open (foreground)
      FirebaseMessaging.onMessage.listen(_showForegroundBanner);

      _listenAuth();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // Upsert the FCM token into device_tokens — safe to call multiple times
  Future<void> _saveToken(String token) async {
    try {
      await Supabase.instance.client.from('device_tokens').upsert(
        {'token': token},
        onConflict: 'token',
      );
    } catch (_) {
      // Non-fatal — app works fine without notification registration
    }
  }

  // Show an in-app banner when a notification arrives in the foreground
  void _showForegroundBanner(RemoteMessage message) {
    if (!mounted) return;
    final notification = message.notification;
    if (notification == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.deepPurple,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title ?? 'New Job',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (notification.body != null)
              Text(notification.body!,
                  style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Connection error: $_error')),
      );
    }
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Colors.deepPurple,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Audio Analyzer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Route based on whether a valid session already exists
    final session = Supabase.instance.client.auth.currentSession;
    return session != null ? const DashboardScreen() : const LoginScreen();
  }
}

// ---------------------------------------------------------------------------
// LoginScreen
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading   = false;
  bool _obscure     = true;
  String? _errorMsg;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      await supabase.auth.signInWithPassword(
        email:    _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Auth state listener in AppLoader handles the navigation automatically
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMsg = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo / title ─────────────────────────────────────────
                const Icon(Icons.headset_mic_rounded,
                    size: 64, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  'Audio Analyzer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Technician Portal',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 14),
                ),
                const SizedBox(height: 36),

                // ── Card ─────────────────────────────────────────────────
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _signIn(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),

                        // Error message
                        if (_errorMsg != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMsg!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Sign in button
                        FilledButton(
                          onPressed: _isLoading ? null : _signIn,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Text('Sign In',
                                  style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard — tab controller lives here so the stream is built once
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Single stream for ALL jobs — filtered per tab + search in the builder
  final Stream<List<Map<String, dynamic>>> _jobsStream = supabase
      .from('jobs')
      .stream(primaryKey: ['id']).order('id', ascending: false);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kTabLabels.length, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Returns true if the job matches the current search query
  bool _matchesSearch(Map<String, dynamic> job) {
    if (_searchQuery.isEmpty) return true;
    final name    = (job['name']    as String? ?? '').toLowerCase();
    final phone   = (job['phone']   as String? ?? '').toLowerCase();
    final address = (job['address'] as String? ?? '').toLowerCase();
    return name.contains(_searchQuery) ||
        phone.contains(_searchQuery) ||
        address.contains(_searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Dispatched Jobs Dashboard'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out?'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepPurple),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await supabase.auth.signOut();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: kTabLabels.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, phone or address…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ── Tab content ───────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _jobsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error loading data: ${snapshot.error}'));
                }

                final allJobs = snapshot.data ?? [];

                return TabBarView(
                  controller: _tabController,
                  children: kTabLabels.map((status) {
                    final filtered = allJobs
                        .where((j) =>
                            (j['status'] ?? kStatusPending) == status &&
                            _matchesSearch(j))
                        .toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No "$status" jobs matching "$_searchQuery".'
                              : 'No "$status" jobs.',
                          style: const TextStyle(
                              fontSize: 16, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          JobCard(job: filtered[index]),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timestamp helper — no extra packages needed
// ---------------------------------------------------------------------------
String _formatTimestamp(String? raw) {
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw)?.toLocal();
  if (dt == null) return '';

  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';

  // Same calendar year → "15 Jan"  |  older → "15 Jan 2024"
  final day   = dt.day.toString();
  const months = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
  final month = months[dt.month - 1];
  final suffix = dt.year == now.year ? '' : ' ${dt.year}';
  return '$day $month$suffix';
}

// ---------------------------------------------------------------------------
// Job card — tappable, shows notes badge when notes exist
// ---------------------------------------------------------------------------
class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job});

  final Map<String, dynamic> job;

  Color _priorityBg(bool isEmergency) =>
      isEmergency ? Colors.red.shade100 : Colors.blue.shade100;

  Color _priorityFg(bool isEmergency) =>
      isEmergency ? Colors.red.shade900 : Colors.blue.shade900;

  Color _statusColor(String status) {
    switch (status) {
      case kStatusBooked:
        return Colors.teal.shade700;
      case kStatusComplete:
        return Colors.green.shade700;
      case kStatusWaiting:
        return Colors.orange.shade700;
      default:
        return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEmergency = job['priority'] == 'Emergency';
    final String status = job['status'] ?? kStatusPending;
    final String? notes = job['notes'] as String?;
    final bool hasNotes = notes != null && notes.trim().isNotEmpty;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isEmergency ? Colors.red : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      job['name'] ?? 'Unknown Client',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Chip(
                    label: Text(job['priority'] ?? 'Standard'),
                    backgroundColor: _priorityBg(isEmergency),
                    labelStyle: TextStyle(
                      color: _priorityFg(isEmergency),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Divider(),

              // ── Contact info ─────────────────────────────────────────────
              Text('📞 Phone: ${job['phone'] ?? 'N/A'}'),
              const SizedBox(height: 4),
              Text('📍 Address: ${job['address'] ?? 'N/A'}'),
              const SizedBox(height: 8),

              // ── AI summary ───────────────────────────────────────────────
              const Text(
                'AI Audio Summary:',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.deepPurple),
              ),
              Text(
                job['summary'] ?? 'No context provided.',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 8),

              // ── Footer row: status + notes indicator ─────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _statusColor(status).withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: _statusColor(status),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                 // Timestamp
                 Text(
                   _formatTimestamp(job['created_at'] as String?),
                   style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                 ),
                 // Notes indicator
                 if (hasNotes)
                   Row(
                     children: [
                       Icon(Icons.note_alt_outlined,
                           size: 14, color: Colors.grey.shade600),
                       const SizedBox(width: 4),
                       Text(
                         'Has notes',
                         style: TextStyle(
                             fontSize: 12, color: Colors.grey.shade600),
                       ),
                     ],
                   ),
                 // Tap hint
                 Text(
                   'Tap for details →',
                   style:
                       TextStyle(fontSize: 11, color: Colors.grey.shade500),
                 ),
                ],
              ),

              // ── Notes preview (if any) ────────────────────────────────────
              if (hasNotes) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          notes,
                          style: TextStyle(
                              fontSize: 13, color: Colors.brown.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => JobDetailSheet(job: job),
    );
  }
}

// ---------------------------------------------------------------------------
// Job detail bottom sheet — status changes + note saving
// ---------------------------------------------------------------------------
class JobDetailSheet extends StatefulWidget {
  const JobDetailSheet({super.key, required this.job});

  final Map<String, dynamic> job;

  @override
  State<JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends State<JobDetailSheet> {
  late String _currentStatus;

  // Booked appointment date/time — null until the user picks one
  DateTime? _bookedAt;

  // Editable job-detail controllers
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _summaryController;
  late final TextEditingController _noteController;

  // Per-field inline error messages
  String? _nameError;
  String? _phoneError;
  String? _addressError;
  String? _summaryError;
  String? _noteError;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    _currentStatus     = job['status']  ?? kStatusPending;
    _nameController    = TextEditingController(text: job['name']    as String? ?? '');
    _phoneController   = TextEditingController(text: job['phone']   as String? ?? '');
    _addressController = TextEditingController(text: job['address'] as String? ?? '');
    _summaryController = TextEditingController(text: job['summary'] as String? ?? '');
    _noteController    = TextEditingController(text: job['notes']   as String? ?? '');
    // Pre-fill booked_at if it was already saved
    final rawBookedAt = job['booked_at'] as String?;
    if (rawBookedAt != null) _bookedAt = DateTime.tryParse(rawBookedAt)?.toLocal();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _summaryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Launch helpers ──────────────────────────────────────────────────────

  Future<void> _launchPhone(String phone) async {
    final cleaned = _phoneController.text.trim().isNotEmpty
        ? _phoneController.text.trim().replaceAll(RegExp(r'[^\d\+\s\-\(\)]'), '')
        : phone.replaceAll(RegExp(r'[^\d\+\s\-\(\)]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No dialler app found on this device.')),
      );
    }
  }

  Future<void> _launchMaps(String address) async {
    final resolvedAddress = _addressController.text.trim().isNotEmpty
        ? _addressController.text.trim()
        : address;
    // Try native geo URI first (opens Google Maps or any maps app)
    final geoUri = Uri(
      scheme: 'geo',
      path: '0,0',
      queryParameters: {'q': resolvedAddress},
    );
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }
    // Fallback: open Google Maps in the browser
    final webUri = Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': resolvedAddress},
    );
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps.')),
      );
    }
  }

  Future<void> _deleteJob() async {
    final jobId = widget.job['id'];
    if (jobId == null) return;

    // Confirmation dialog — user must explicitly confirm before deletion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Job?'),
        content: Text(
          'Are you sure you want to permanently delete the job for '
          '"${widget.job['name'] ?? 'this client'}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await supabase.from('jobs').delete().eq('id', jobId);
      if (mounted) {
        Navigator.of(context).pop(); // close the bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job deleted.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Returns an error string if invalid, null if valid.
  String? _validateRequired(String value, String fieldName) {
    if (value.trim().isEmpty) return '$fieldName cannot be empty.';
    return null;
  }

  // Opens the system date + time pickers and stores the result in _bookedAt
  Future<void> _pickBookedAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _bookedAt ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_bookedAt ?? DateTime.now()),
    );
    if (time == null || !mounted) return;

    setState(() {
      _bookedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // Adds the booked appointment to the device's native calendar
  void _launchCalendar() {
    if (_bookedAt == null) return;
    final endTime = _bookedAt!.add(const Duration(hours: 1));
    final event = Event(
      title: '🔧 Job: ${_nameController.text.trim()}',
      description: _summaryController.text.trim(),
      location: _addressController.text.trim(),
      startDate: _bookedAt!,
      endDate: endTime,
    );
    Add2Calendar.addEvent2Cal(event);
  }

  Future<void> _saveChanges() async {
    final jobId = widget.job['id'];
    if (jobId == null) return;

    // Validate all required fields
    final nameErr    = _validateRequired(_nameController.text,    'Name');
    final phoneErr   = _validateRequired(_phoneController.text,   'Phone');
    final addressErr = _validateRequired(_addressController.text, 'Address');
    final summaryErr = _validateRequired(_summaryController.text, 'Summary');
    final noteText   = _noteController.text;
    final noteErr    = (noteText.isNotEmpty && noteText.trim().isEmpty)
        ? 'Notes cannot be blank — add content or clear the field.'
        : null;

    if (nameErr != null || phoneErr != null ||
        addressErr != null || summaryErr != null || noteErr != null) {
      setState(() {
        _nameError    = nameErr;
        _phoneError   = phoneErr;
        _addressError = addressErr;
        _summaryError = summaryErr;
        _noteError    = noteErr;
      });
      return;
    }

    setState(() => _isSaving = true);
    try {
      await supabase.from('jobs').update({
        'name':      _nameController.text.trim(),
        'phone':     _phoneController.text.trim(),
        'address':   _addressController.text.trim(),
        'summary':   _summaryController.text.trim(),
        'status':    _currentStatus,
        'notes':     _noteController.text.trim(),
        'booked_at': _bookedAt?.toUtc().toIso8601String(),
      }).eq('id', jobId);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Reusable field builder ───────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? errorText,
    void Function(String)? onChanged,
    int maxLines = 1,
    TextInputType? keyboardType,
    IconData? prefixIcon,
    String? hintText,
    TextStyle? style,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: style,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        errorText: errorText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Editable: Client name ─────────────────────────────────────
            _buildField(
              controller: _nameController,
              label: 'Client Name',
              errorText: _nameError,
              onChanged: (_) { if (_nameError != null) setState(() => _nameError = null); },
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // ── Editable: Phone ───────────────────────────────────────────
            _buildField(
              controller: _phoneController,
              label: 'Phone',
              errorText: _phoneError,
              onChanged: (_) { if (_phoneError != null) setState(() => _phoneError = null); },
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
            ),
            const SizedBox(height: 10),

            // ── Editable: Address ─────────────────────────────────────────
            _buildField(
              controller: _addressController,
              label: 'Address',
              errorText: _addressError,
              onChanged: (_) { if (_addressError != null) setState(() => _addressError = null); },
              prefixIcon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 12),

            // ── Quick-action buttons (use live controller values) ──────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final phone = _phoneController.text.trim();
                      if (phone.isNotEmpty) _launchPhone(phone);
                    },
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: const Text('Call Customer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final address = _addressController.text.trim();
                      if (address.isNotEmpty) _launchMaps(address);
                    },
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('Open in Maps'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      side: BorderSide(color: Colors.blue.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // ── Editable: AI summary ──────────────────────────────────────
            _buildField(
              controller: _summaryController,
              label: 'AI Audio Summary',
              errorText: _summaryError,
              onChanged: (_) { if (_summaryError != null) setState(() => _summaryError = null); },
              maxLines: 3,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),

            // ── Status selector ──────────────────────────────────────────
            const Text('Job Status:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: kTabLabels.map((status) {
                final selected = _currentStatus == status;
                return ChoiceChip(
                  label: Text(status),
                  selected: selected,
                  onSelected: (_) => setState(() => _currentStatus = status),
                  selectedColor: Colors.deepPurple.shade100,
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.deepPurple.shade900
                        : Colors.grey.shade700,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Booked appointment (only shown when status = Booked) ──────
            if (_currentStatus == kStatusBooked) ...[
              const Text('Appointment Date & Time:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickBookedAt,
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(
                        _bookedAt == null
                            ? 'Pick date & time'
                            : '${_bookedAt!.day}/${_bookedAt!.month}/${_bookedAt!.year}  ${_bookedAt!.hour.toString().padLeft(2, '0')}:${_bookedAt!.minute.toString().padLeft(2, '0')}',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal.shade700,
                        side: BorderSide(color: Colors.teal.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_bookedAt != null) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _launchCalendar,
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: const Text('Add to Calendar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal.shade700,
                        side: BorderSide(color: Colors.teal.shade400),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
            ],

            // ── Notes field ──────────────────────────────────────────────
            _buildField(
              controller: _noteController,
              label: 'Technician Notes',
              errorText: _noteError,
              onChanged: (_) { if (_noteError != null) setState(() => _noteError = null); },
              maxLines: 4,
              hintText: 'Parts used, findings, follow-up actions…',
            ),
            const SizedBox(height: 20),

            // ── Save + Delete buttons ────────────────────────────────────
            Row(
              children: [
                // Delete button
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _deleteJob,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade400),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                  ),
                ),
                const SizedBox(width: 10),
                // Save button — takes remaining width
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveChanges,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_isSaving ? 'Saving…' : 'Save Changes'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
