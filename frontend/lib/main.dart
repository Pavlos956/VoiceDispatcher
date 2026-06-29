import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // 1. Ensure Flutter engine bindings are fully ready before initializing APIs
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Supabase Connection
  // REPLACE THESE STRING VALUES WITH YOUR ACTUAL SUPABASE CREDENTIALS
  await Supabase.initialize(
    url: 'https://oogjreozyrdcprechvnj.supabase.co', 
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vZ2pyZW96eXJkY3ByZWNodm5qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzNzY0NjUsImV4cCI6MjA5Nzk1MjQ2NX0.TtEUlyeE5L05H3NCCewPEpLrPSO7DmsMCiY_O9ng4fg', 
  );

  runApp(const MyApp());
}

// Global shortcut variable to interact with Supabase anywhere in the app
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Technician Dashboard',
      debugShowCheckedModeBanner: false, // Removes the red debug banner
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 3. Establish a live real-time websocket stream tracking your 'jobs' table
    final Stream<List<Map<String, dynamic>>> _jobsStream = supabase
        .from('jobs')
        .stream(primaryKey: ['id']) 
        .order('id', ascending: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Dispatched Jobs Dashboard'),
        backgroundColor: Colors.deepPurple, // Fixed: changed 'deepPurpleContainer' to 'deepPurple'
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _jobsStream,
        builder: (context, snapshot) {
          // State A: App is establishing the cloud connection
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          // State B: Database connection error occurred
          if (snapshot.hasError) {
            return Center(child: Text('Error loading data: ${snapshot.error}'));
          }

          final jobs = snapshot.data ?? [];

          // State C: Table is empty
          if (jobs.isEmpty) {
            return const Center(
              child: Text(
                'No jobs assigned yet.\nRun your Python script to push data!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          // State D: Render list of real-time database cards
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              final bool isEmergency = job['priority'] == 'Emergency';

              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: isEmergency ? Colors.red : Colors.transparent, 
                    width: 2
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Fixed
                        children: [
                          Text(
                            job['name'] ?? 'Unknown Client',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Chip(
                            label: Text(job['priority'] ?? 'Standard'),
                            backgroundColor: isEmergency ? Colors.red.shade100 : Colors.blue.shade100,
                            labelStyle: TextStyle( // Fixed parameter mapping
                              color: isEmergency ? Colors.red.shade900 : Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 4),
                      Text('📞 Phone: ${job['phone'] ?? 'N/A'}'),
                      const SizedBox(height: 4),
                      Text('📍 Address: ${job['address'] ?? 'N/A'}'),
                      const SizedBox(height: 8),
                      const Text(
                        'AI Audio Summary:', 
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)
                      ),
                      Text(
                        job['summary'] ?? 'No context provided.',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}