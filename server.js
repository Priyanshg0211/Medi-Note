const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(morgan('combined'));
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: '50mb' }));
app.use(express.raw({ type: 'audio/*', limit: '50mb' }));

// In-memory storage (for demo purposes)
let sessions = {};
let patients = [];
let users = [];
let templates = [];

// Initialize with demo data
const initializeDemoData = () => {
  // Add demo user
  users.push({
    id: 'user_123',
    email: 'doctor@example.com',
    name: 'Dr. Smith'
  });

  // Add demo patient
  patients.push({
    id: 'patient_123',
    name: 'John Doe',
    user_id: 'user_123',
    pronouns: 'he/him',
    email: 'john@example.com',
    background: 'Regular checkup patient',
    medical_history: 'No significant history',
    family_history: 'Father has diabetes',
    social_history: 'Non-smoker, occasional drinker',
    previous_treatment: 'Annual physicals'
  });

  // Add demo template
  templates.push({
    id: 'template_123',
    title: 'New Patient Visit',
    type: 'default',
    user_id: 'user_123',
    content: 'Standard new patient consultation template'
  });
};

// Initialize demo data
initializeDemoData();

// Patient Management Endpoints
app.get('/api/v1/patients', (req, res) => {
  const { userId } = req.query;
  console.log('GET /patients - userId:', userId);

  const result = userId ? patients.filter(p => p.user_id === userId) : patients;
  res.json({
    patients: result
  });
});

app.post('/api/v1/add-patient-ext', (req, res) => {
  const { name, userId, pronouns, email, background, medical_history, family_history, social_history, previous_treatment } = req.body;
  
  if (!name || !userId) {
    return res.status(400).json({ error: 'name and userId are required' });
  }

  const newPatient = {
    id: `patient_${Date.now()}`,
    name: name,
    user_id: userId,
    pronouns: pronouns || null,
    email: email || null,
    background: background || null,
    medical_history: medical_history || null,
    family_history: family_history || null,
    social_history: social_history || null,
    previous_treatment: previous_treatment || null
  };

  patients.push(newPatient);
  console.log('POST /add-patient-ext - Created:', newPatient);

  res.status(201).json({
    patient: newPatient
  });
});

app.get('/api/v1/patient-details/:patientId', (req, res) => {
  const { patientId } = req.params;
  console.log('GET /patient-details - patientId:', patientId);

  const patient = patients.find(p => p.id === patientId);
  if (!patient) return res.status(404).json({ error: 'Patient not found' });
  res.json(patient);
});

// Recording Session Management - CORE FUNCTIONALITY
app.post('/api/v1/upload-session', (req, res) => {
  const { patientId, userId, patientName, status, startTime, templateId } = req.body;
  
  if (!patientId || !userId) {
    return res.status(400).json({ error: 'patientId and userId are required' });
  }

  const sessionId = `session_${Date.now()}`;
  sessions[sessionId] = {
    id: sessionId,
    patientId,
    userId,
    patientName: patientName || null,
    status: status || 'recording',
    startTime: startTime || new Date().toISOString(),
    endTime: null,
    templateId: templateId || null,
    chunks: [],
    totalChunksReceived: 0,
    lastChunkTime: null
  };

  console.log('POST /upload-session - Created session:', sessionId);
  res.status(201).json({ id: sessionId });
});

app.post('/api/v1/get-presigned-url', (req, res) => {
  const { sessionId, chunkNumber, mimeType } = req.body;
  
  if (!sessionId || typeof chunkNumber === 'undefined') {
    return res.status(400).json({ error: 'sessionId and chunkNumber are required' });
  }

  // Mock presigned URL for demo - in production this would be real GCS/S3
  const mockPresignedUrl = `http://localhost:${PORT}/mock-gcs-upload/${sessionId}/${chunkNumber}`;
  const extension = mimeType && mimeType.includes('mp3') ? 'mp3' : 'wav';
  const gcsPath = `sessions/${sessionId}/chunk_${chunkNumber}.${extension}`;
  const publicUrl = `http://localhost:${PORT}/audio/${sessionId}/${chunkNumber}`;

  console.log('POST /get-presigned-url - Session:', sessionId, 'Chunk:', chunkNumber);

  res.json({
    url: mockPresignedUrl,
    gcsPath: gcsPath,
    publicUrl: publicUrl
  });
});

// Mock GCS upload endpoint - simulates cloud storage
app.put('/mock-gcs-upload/:sessionId/:chunkNumber', (req, res) => {
  const { sessionId, chunkNumber } = req.params;
  const audioData = req.body;

  console.log('PUT /mock-gcs-upload - Received chunk:', chunkNumber, 'for session:', sessionId);
  console.log('Chunk size:', audioData.length, 'bytes');

  // In a real implementation, this would upload to GCS/S3
  // For demo, we just acknowledge receipt
  res.status(200).send('');
});

app.post('/api/v1/notify-chunk-uploaded', (req, res) => {
  const {
    sessionId,
    gcsPath,
    chunkNumber,
    isLast,
    totalChunksClient,
    publicUrl,
    mimeType,
    selectedTemplate,
    selectedTemplateId,
    model
  } = req.body;

  if (sessions[sessionId]) {
    sessions[sessionId].chunks.push({
      chunkNumber,
      gcsPath,
      publicUrl,
      mimeType,
      uploadedAt: new Date().toISOString()
    });

    sessions[sessionId].totalChunksReceived++;
    sessions[sessionId].lastChunkTime = new Date().toISOString();

    console.log('POST /notify-chunk-uploaded - Session:', sessionId, 'Chunk:', chunkNumber);
    console.log('Total chunks received:', sessions[sessionId].totalChunksReceived);
    console.log('Is last chunk:', isLast);

    if (isLast) {
      sessions[sessionId].status = 'completed';
      sessions[sessionId].endTime = new Date().toISOString();
      console.log('Session completed:', sessionId);
    }
  }

  res.json({});
});

// User Management
app.get('/api/users/asd3fd2faec', (req, res) => {
  const { email } = req.query;
  const user = users.find(u => u.email === email);
  if (user) {
    return res.json({ id: user.id, email: user.email, name: user.name || null });
  }
  return res.status(404).json({ error: 'User not found' });
});

app.post('/api/users', (req, res) => {
  const { email, name } = req.body;
  if (!email) return res.status(400).json({ error: 'email is required' });
  
  const existing = users.find(u => u.email === email);
  if (existing) return res.status(200).json(existing);
  
  const user = { id: `user_${Date.now()}`, email, name: name || null };
  users.push(user);
  res.status(201).json(user);
});

// Template Management
app.get('/api/v1/fetch-default-template-ext', (req, res) => {
  const { userId } = req.query;
  console.log('GET /fetch-default-template-ext - userId:', userId);
  
  const data = userId ? templates.filter(t => t.user_id === userId) : templates;
  res.json({ success: true, data });
});

// Session details for debugging
app.get('/api/v1/session/:id', (req, res) => {
  const { id } = req.params;
  const session = sessions[id];
  if (!session) return res.status(404).json({ error: 'Session not found' });
  res.json(session);
});

// Get all sessions for a user
app.get('/api/v1/all-session', (req, res) => {
  const { userId } = req.query;
  console.log('GET /all-session - userId:', userId);

  const userSessions = Object.values(sessions).filter(s => s.userId === userId);

  res.json({
    sessions: userSessions.map(session => ({
      id: session.id,
      user_id: session.userId,
      patient_id: session.patientId,
      patient_name: session.patientName,
      status: session.status,
      start_time: session.startTime,
      end_time: session.endTime,
      total_chunks: session.totalChunksReceived,
      last_chunk_time: session.lastChunkTime
    }))
  });
});

// Debug endpoint
app.get('/debug/sessions', (req, res) => {
  res.json({
    sessions: sessions,
    totalSessions: Object.keys(sessions).length,
    patients: patients,
    users: users,
    templates: templates
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    version: '1.0.0',
    activeSessions: Object.keys(sessions).length
  });
});

// Error handling
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({
    error: 'Internal server error',
    details: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Endpoint not found',
    path: req.path,
    method: req.method
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('\n🚀 MediNote Backend Server Started');
  console.log(`📍 Server running on http://0.0.0.0:${PORT}`);
  console.log(`🔍 Health check: http://localhost:${PORT}/health`);
  console.log(`🐛 Debug endpoint: http://localhost:${PORT}/debug/sessions`);
  console.log('\n📋 Core API Endpoints:');
  console.log('   Patient Management:');
  console.log('     GET  /api/v1/patients');
  console.log('     POST /api/v1/add-patient-ext');
  console.log('     GET  /api/v1/patient-details/:id');
  console.log('   Recording Management:');
  console.log('     POST /api/v1/upload-session');
  console.log('     POST /api/v1/get-presigned-url');
  console.log('     POST /api/v1/notify-chunk-uploaded');
  console.log('     PUT  /mock-gcs-upload/:sessionId/:chunkNumber');
  console.log('   User Management:');
  console.log('     GET  /api/users/asd3fd2faec');
  console.log('     POST /api/users');
  console.log('   Template Management:');
  console.log('     GET  /api/v1/fetch-default-template-ext');
  console.log('\n💡 Ready for Flutter app connections!');
  console.log('📱 Demo data loaded: 1 user, 1 patient, 1 template');
});
