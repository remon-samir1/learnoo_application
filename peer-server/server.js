const { ExpressPeerServer } = require('peer');
const express = require('express');

const app = express();

// Enable JSON body parsing
app.use(express.json());

// Health check endpoint
app.get('/', (req, res) => {
  res.json({
    name: 'Learnoo PeerJS Server',
    description: 'Custom PeerJS signaling server for Learnoo',
    website: 'https://peerjs.com/'
  });
});

app.get('/server', (req, res) => {
  res.json({
    name: 'PeerJS Server',
    description: 'A server side element to broker connections between PeerJS clients.',
    website: 'https://peerjs.com/'
  });
});

// Configure PeerJS server
const server = app.listen(process.env.PORT || 443, () => {
  console.log(`PeerJS Server running on port ${process.env.PORT || 443}`);
});

const peerServer = ExpressPeerServer(server, {
  debug: true,
  path: '/peerjs',
  proxied: true,
  allow_discovery: true,
  secure: true,
});

app.use('/', peerServer);

// Handle peer server errors
peerServer.on('connection', (client) => {
  console.log(`Client connected: ${client.getId()}`);
});

peerServer.on('disconnect', (client) => {
  console.log(`Client disconnected: ${client.getId()}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
