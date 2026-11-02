const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 3000;
const APP_ENV = process.env.APP_ENV || 'local';

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      uptime: process.uptime(),
      env: APP_ENV,
      hostname: os.hostname()
    }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    message: 'Containerized Node.js API on ECS Fargate',
    env: APP_ENV,
    hostname: os.hostname()
  }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`API listening on port ${PORT} in env=${APP_ENV}`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => process.exit(0));
});

