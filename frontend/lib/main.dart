import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Show the app shell immediately — Supabase init happens inside AppLoader
  // so the UI thread is never blocked during startup.
  runApp(const MyApp());
}

// Accessed only after AppLoader confirms Supabase is ready.
SupabaseClient get supabase => Supabase.instance.client;

// ---------------------------------------------------------------------------
// Status constants — must match the values stored in Supabase
// ---------------------------------------------------------------------------
const String kStatusPending = 'Pending';
const String kStatusComplete = 'Complete';
const String kStatusWaiting = 'To Be Called';

const List<String> kTabLabels = [
  kStatusPending,
  kStatusComplete,
  kStatusWaiting,
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

  Future<void> _init() async {
    try {
      await Supabase.initialize(
        url: 'https://oogjreozyrdcprechvnj.supabase.co',
        publishableKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vZ2pyZW96eXJkY3ByZWNodm5qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzNzY0NjUsImV4cCI6MjA5Nzk1MjQ2NX0.TtEUlyeE5L05H3NCCewPEpLrPSO7DmsMCiY_O9ng4fg',
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
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
    return const DashboardScreen();
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

  // Single stream for ALL jobs — filtered per tab in the builder
  final Stream<List<Map<String, dynamic>>> _jobsStream = supabase
      .from('jobs')
      .stream(primaryKey: ['id']).order('id', ascending: false);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kTabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Dispatched Jobs Dashboard'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: kTabLabels
              .map((label) => Tab(text: label))
              .toList(),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
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
                  .where((j) => (j['status'] ?? kStatusPending) == status)
                  .toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No "$status" jobs.',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  return JobCard(job: filtered[index]);
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
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
  late final TextEditingController _noteController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.job['status'] ?? kStatusPending;
    _noteController =
        TextEditingController(text: widget.job['notes'] as String? ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final jobId = widget.job['id'];
    if (jobId == null) return;

    setState(() => _isSaving = true);
    try {
      await supabase.from('jobs').update({
        'status': _currentStatus,
        'notes': _noteController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
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

            // ── Client name + priority ───────────────────────────────────
            Text(
              job['name'] ?? 'Unknown Client',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('📞 ${job['phone'] ?? 'N/A'}  •  📍 ${job['address'] ?? 'N/A'}',
                style: TextStyle(color: Colors.grey.shade600)),
            const Divider(height: 24),

            // ── AI summary ───────────────────────────────────────────────
            const Text('AI Audio Summary:',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            Text(job['summary'] ?? 'No context provided.',
                style: const TextStyle(fontStyle: FontStyle.italic)),
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

            // ── Notes field ──────────────────────────────────────────────
            const Text('Technician Notes:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'Add notes visible to all technicians (parts used, findings, follow-up actions…)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 20),

            // ── Save button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
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
                label:
                    Text(_isSaving ? 'Saving…' : 'Save Changes'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
