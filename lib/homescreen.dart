import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recording_provider.dart';
import '../services/api_service.dart';
import '../models/patient.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  List<Patient> _patients = [];
  Patient? _selectedPatient;
  bool _isLoading = false;
  bool _useExisting = true; // toggle between existing and new patient
  bool _isCreatingPatient = false;
  final TextEditingController _patientNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // Initialize pulse animation for recording indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _initializeProvider();
    _loadPatients();
  }

  Future<void> _initializeProvider() async {
    final provider = context.read<RecordingProvider>();
    await provider.initialize();
  }

  Future<void> _loadPatients() async {
    setState(() => _isLoading = true);
    try {
      final patients = await ApiService.getPatients(userId: 'user_123');
      setState(() {
        _patients = patients;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load patients: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _patientNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'MediNote',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: const Color(0xFFE2E8F0),
            height: 1.0,
          ),
        ),
      ),
      body: Consumer<RecordingProvider>(
        builder: (context, provider, child) {
          // Start pulse animation when recording
          if (provider.isRecording && !_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          } else if (!provider.isRecording) {
            _pulseController.stop();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Card
                _buildStatusCard(provider),
                
                const SizedBox(height: 24),
                
                // Patient Selection
                _buildPatientSection(),
                
                const SizedBox(height: 32),
                
                // Recording Controls
                _buildRecordingControls(provider),
                
                const SizedBox(height: 24),
                
                // Audio Visualizer
                if (provider.isRecording || provider.isPaused)
                  _buildAudioVisualizer(provider),
                
                const SizedBox(height: 24),
                
                // Recording Info
                if (provider.isRecording || provider.isPaused)
                  _buildRecordingInfo(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(RecordingProvider provider) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (provider.state) {
      case RecordingState.recording:
        statusColor = Colors.red;
        statusText = 'Recording in Progress';
        statusIcon = Icons.fiber_manual_record;
        break;
      case RecordingState.paused:
        statusColor = Colors.orange;
        statusText = 'Recording Paused';
        statusIcon = Icons.pause;
        break;
      case RecordingState.starting:
        statusColor = Colors.blue;
        statusText = 'Starting Recording...';
        statusIcon = Icons.play_arrow;
        break;
      case RecordingState.error:
        statusColor = Colors.red;
        statusText = 'Error Occurred';
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Ready to Record';
        statusIcon = Icons.mic;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      provider.isOnline ? Icons.cloud_done : Icons.cloud_off,
                      size: 16,
                      color: provider.isOnline ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      provider.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 14,
                        color: provider.isOnline ? Colors.green : Colors.red,
                      ),
                    ),
                    if (provider.pendingChunksCount > 0) ...[
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.pending,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${provider.pendingChunksCount} pending',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          // Mode toggle: Existing vs New
          Row(
            children: [
              ChoiceChip(
                label: const Text('Existing'),
                selected: _useExisting,
                onSelected: (v) {
                  setState(() {
                    _useExisting = true;
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('New'),
                selected: !_useExisting,
                onSelected: (v) {
                  setState(() {
                    _useExisting = false;
                    _selectedPatient = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Existing patient dropdown or New patient text field
          if (_useExisting)
            DropdownButtonFormField<Patient>(
              value: _selectedPatient,
              decoration: InputDecoration(
                labelText: 'Select Patient',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              items: _patients.map((patient) {
                return DropdownMenuItem(
                  value: patient,
                  child: Text(patient.name),
                );
              }).toList(),
              onChanged: (patient) {
                setState(() {
                  _selectedPatient = patient;
                  _patientNameController.text = patient?.name ?? '';
                });
              },
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _patientNameController,
                  decoration: InputDecoration(
                    labelText: 'New Patient Name',
                    hintText: 'Enter new patient name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: _patientNameController.text.isEmpty || _isCreatingPatient
                        ? null
                        : () async {
                            setState(() => _isCreatingPatient = true);
                            try {
                              final newPatient = await ApiService.addPatient(
                                name: _patientNameController.text,
                                userId: 'user_123',
                              );
                              setState(() {
                                _patients.insert(0, newPatient);
                                _selectedPatient = newPatient;
                                _useExisting = true;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Patient added')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to add patient: $e')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _isCreatingPatient = false);
                            }
                          },
                    icon: _isCreatingPatient
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: const Text('Save New Patient'),
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 12),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            TextButton.icon(
              onPressed: _loadPatients,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Patients'),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls(RecordingProvider provider) {
    final canStartRecording = (provider.state == RecordingState.idle || provider.state == RecordingState.stopped) && 
        (
          (_useExisting && _selectedPatient != null) ||
          (!_useExisting && _patientNameController.text.isNotEmpty)
        );
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main Record Button
          GestureDetector(
            onTap: provider.isRecording 
                ? () => provider.stopRecording()
                : canStartRecording 
                    ? () => _startRecording(provider) 
                    : null,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: provider.isRecording ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: provider.isRecording 
                          ? Colors.red 
                          : canStartRecording 
                              ? Colors.blue 
                              : Colors.grey,
                      boxShadow: [
                        BoxShadow(
                          color: (provider.isRecording ? Colors.red : Colors.blue)
                              .withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: provider.isRecording ? 10 : 0,
                        ),
                      ],
                    ),
                    child: Icon(
                      provider.isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            provider.isRecording 
                ? 'Tap to Stop Recording' 
                : canStartRecording
                    ? 'Tap to Start Recording'
                    : 'Select a patient to start',
            style: TextStyle(
              fontSize: 16,
              color: canStartRecording ? const Color(0xFF1E293B) : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Control Buttons
          if (provider.isRecording || provider.isPaused)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  icon: provider.isPaused ? Icons.play_arrow : Icons.pause,
                  label: provider.isPaused ? 'Resume' : 'Pause',
                  onPressed: provider.isPaused 
                      ? () => provider.resumeRecording()
                      : () => provider.pauseRecording(),
                  color: Colors.orange,
                ),
                _buildControlButton(
                  icon: Icons.stop,
                  label: 'Stop',
                  onPressed: () => provider.stopRecording(),
                  color: Colors.red,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.1),
            border: Border.all(color: color, width: 2),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioVisualizer(RecordingProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Audio Level',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          
          // Audio Level Bar
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: provider.audioLevel,
              child: Container(
                decoration: BoxDecoration(
                  color: provider.audioLevel > 0.7 
                      ? Colors.red 
                      : provider.audioLevel > 0.4 
                          ? Colors.orange 
                          : Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Level Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Level: ${(provider.audioLevel * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: provider.audioLevel > 0.1 
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  provider.audioLevel > 0.1 ? 'Detecting Audio' : 'Silent',
                  style: TextStyle(
                    fontSize: 12,
                    color: provider.audioLevel > 0.1 ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingInfo(RecordingProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recording Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          
          _buildInfoRow('Patient', provider.patientName ?? 'Unknown'),
          _buildInfoRow('Duration', provider.formatDuration(provider.duration)),
          _buildInfoRow('Session ID', provider.sessionId ?? 'N/A'),
          
          if (provider.pendingChunksCount > 0)
            _buildInfoRow(
              'Pending Uploads', 
              '${provider.pendingChunksCount} chunks',
              isWarning: true,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isWarning ? Colors.orange : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording(RecordingProvider provider) async {
    if ((_useExisting && _selectedPatient == null) ||
        (!_useExisting && _patientNameController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter a patient')),
      );
      return;
    }

    try {
      String patientId;
      String patientName = _patientNameController.text;
      if (_useExisting) {
        patientId = _selectedPatient!.id;
        patientName = _selectedPatient!.name;
      } else {
        // Auto-create patient if starting directly in New mode
        setState(() => _isCreatingPatient = true);
        final newPatient = await ApiService.addPatient(
          name: _patientNameController.text,
          userId: 'user_123',
        );
        setState(() {
          _patients.insert(0, newPatient);
          _selectedPatient = newPatient;
          _useExisting = true;
          _isCreatingPatient = false;
        });
        patientId = newPatient.id;
        patientName = newPatient.name;
      }
      
      await provider.startRecording(
        patientId: patientId,
        patientName: patientName,
      );

      if (provider.state == RecordingState.error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start recording. Check permissions.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}