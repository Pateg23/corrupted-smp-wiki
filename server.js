const express = require('express');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const crypto = require('crypto');

// === LOAD .ENV ===
const envFile = path.join(__dirname, '.env');
if (fs.existsSync(envFile)) {
  const lines = fs.readFileSync(envFile, 'utf8').split('\n');
  for (const line of lines) {
    const m = line.trim().match(/^([^=]+)=(.*)$/);
    if (m) process.env[m[1]] = m[2];
  }
}

const app = express();
const PORT = parseInt(process.env.PORT || '8420');
const PUBLIC = path.join(__dirname, 'public');
const CONTENT_FILE = path.join(PUBLIC, 'content.json');
const IMAGES_DIR = path.join(PUBLIC, 'images');
const BACKUP_DIR = path.join(__dirname, 'backups');
const TEMPLATE_FILE = path.join(__dirname, 'wiki-template.html');
const CMS_PASSWORD = process.env.CMS_PASSWORD || 'changeme';
const CLOUDFLARE_API_TOKEN = process.env.CLOUDFLARE_API_TOKEN || '';
const CLOUDFLARE_ACCOUNT_ID = process.env.CLOUDFLARE_ACCOUNT_ID || '';
const CLOUDFLARE_PROJECT_NAME = process.env.CLOUDFLARE_PROJECT_NAME || 'corrupted-smp';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || '';

[BACKUP_DIR, IMAGES_DIR].forEach(d => fs.mkdirSync(d, { recursive: true }));

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-CMS-Password, X-Session-Token');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

app.use(express.static(PUBLIC));

// === SESSION MANAGEMENT ===
const sessions = new Map();

function createSession(ip) {
  const token = crypto.randomBytes(32).toString('hex');
  sessions.set(token, { ip, expiresAt: Date.now() + 24 * 60 * 60 * 1000 });
  return token;
}

function isValidSession(req) {
  const token = req.headers['x-session-token'];
  if (!token) return false;
  const session = sessions.get(token);
  if (!session) return false;
  if (Date.now() > session.expiresAt) { sessions.delete(token); return false; }
  return true;
}

setInterval(() => {
  const now = Date.now();
  for (const [token, s] of sessions) {
    if (now > s.expiresAt) sessions.delete(token);
  }
}, 10 * 60 * 1000);

function auth(req, res, next) {
  if (isValidSession(req)) return next();
  const pw = req.headers['x-cms-password'];
  if (pw === CMS_PASSWORD) return next();
  return res.status(401).json({ error: 'Unauthorized — login first' });
}

app.post('/api/login', (req, res) => {
  const { password } = req.body;
  if (password !== CMS_PASSWORD) return res.status(401).json({ error: 'Wrong password' });
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
  const token = createSession(ip);
  res.json({ success: true, token, expiresIn: '24h' });
});

app.get('/api/session', (req, res) => {
  if (isValidSession(req)) return res.json({ valid: true });
  res.json({ valid: false });
});

app.get('/api/content', (req, res) => {
  try { res.type('application/json').sendFile(CONTENT_FILE); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/save', auth, (req, res) => {
  let data = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  if (!data.weapons || !data.ranks) return res.status(400).json({ error: 'Missing sections' });

  try {
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    if (fs.existsSync(CONTENT_FILE)) fs.copyFileSync(CONTENT_FILE, path.join(BACKUP_DIR, `content-${ts}.json`));
    const backups = fs.readdirSync(BACKUP_DIR).filter(f => f.startsWith('content-')).sort().reverse();
    backups.slice(50).forEach(f => fs.unlinkSync(path.join(BACKUP_DIR, f)));
  } catch (e) {}

  try {
    fs.writeFileSync(CONTENT_FILE, JSON.stringify(data, null, 2), 'utf8');
    // Auto-generate wiki HTML
    try {
      execSync(`python3 generate.py public/content.json wiki-template.html public/index.html`, { cwd: __dirname, timeout: 30000 });
    } catch (genErr) {}
    res.json({ success: true, size: JSON.stringify(data).length });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/images', (req, res) => {
  try {
    const files = fs.readdirSync(IMAGES_DIR).filter(f => /\.(png|jpg|jpeg|gif|svg|webp)$/i.test(f));
    res.json(files);
  } catch (e) { res.json([]); }
});

app.post('/api/upload', auth, (req, res) => {
  const { filename, data } = req.body;
  if (!filename || !data) return res.status(400).json({ error: 'Missing filename or data' });
  const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, '_');
  try {
    const buffer = Buffer.from(data, 'base64');
    fs.writeFileSync(path.join(IMAGES_DIR, safeName), buffer);
    res.json({ success: true, filename: safeName, size: buffer.length });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.delete('/api/images/:name', auth, (req, res) => {
  try {
    const fp = path.join(IMAGES_DIR, req.params.name);
    if (fs.existsSync(fp)) fs.unlinkSync(fp);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/backups', auth, (req, res) => {
  try {
    const files = fs.readdirSync(BACKUP_DIR).filter(f => f.startsWith('content-')).sort().reverse().slice(0, 50);
    res.json(files);
  } catch (e) { res.json([]); }
});

app.post('/api/restore', auth, (req, res) => {
  const { filename } = req.body;
  if (!filename) return res.status(400).json({ error: 'No filename' });
  const bp = path.join(BACKUP_DIR, filename);
  if (!fs.existsSync(bp)) return res.status(404).json({ error: 'Not found' });
  try {
    const data = JSON.parse(fs.readFileSync(bp, 'utf8'));
    fs.writeFileSync(CONTENT_FILE, JSON.stringify(data, null, 2), 'utf8');
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// === WIKI GENERATION ===
app.post('/api/generate', auth, (req, res) => {
  try {
    const output = execSync(`python3 generate.py public/content.json wiki-template.html public/index.html`, { cwd: __dirname, timeout: 30000, encoding: 'utf8' });
    const stats = fs.statSync(path.join(PUBLIC, 'index.html'));
    res.json({ success: true, size: stats.size, output: output.trim() });
  } catch (e) { res.status(500).json({ error: e.message, output: e.stderr || '' }); }
});

// === DEPLOY TO CLOUDFLARE ===
app.post('/api/deploy', auth, (req, res) => {
  try {
    execSync(`python3 generate.py public/content.json wiki-template.html public/index.html`, { cwd: __dirname, timeout: 30000 });
    if (!CLOUDFLARE_API_TOKEN || !CLOUDFLARE_ACCOUNT_ID) {
      return res.json({ success: true, note: 'Generated locally (no Cloudflare configured)' });
    }
    const env = `CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN} CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}`;
    const cmd = `${env} wrangler pages deploy ${PUBLIC} --project-name=${CLOUDFLARE_PROJECT_NAME} --branch=main 2>&1`;
    const output = execSync(cmd, { timeout: 120000, encoding: 'utf8' });
    res.json({ success: true, output: output.slice(-500) });
  } catch (e) { res.status(500).json({ error: e.message, output: e.stdout ? e.stdout.slice(-500) : '' }); }
});

// === PUBLISH: save + generate + deploy + git push ===
app.post('/api/publish', auth, (req, res) => {
  let data = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  if (!data.weapons || !data.ranks) return res.status(400).json({ error: 'Missing sections' });
  try {
    fs.writeFileSync(CONTENT_FILE, JSON.stringify(data, null, 2), 'utf8');
    execSync(`python3 generate.py public/content.json wiki-template.html public/index.html`, { cwd: __dirname, timeout: 30000 });
    if (CLOUDFLARE_API_TOKEN && CLOUDFLARE_ACCOUNT_ID) {
      const env = `CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN} CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}`;
      execSync(`${env} wrangler pages deploy ${PUBLIC} --project-name=${CLOUDFLARE_PROJECT_NAME} --branch=main`, { timeout: 120000 });
    }
    // Push content to GitHub so the repo is always up-to-date
    try {
      execSync(`git add public/content.json public/images/ public/index.html`, { cwd: __dirname });
      execSync(`git diff --cached --quiet || git commit -m "Auto-save [$(date -u +%Y-%m-%dT%H:%M:%SZ)]"`, { cwd: __dirname });
      execSync(`git push`, { cwd: __dirname });
    } catch (gitErr) { /* git push may fail if no changes or token issues — non-critical */ }
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Corrupted SMP CMS running on http://0.0.0.0:${PORT}`);
  console.log(`  CMS: http://localhost:${PORT}/admin/`);
});
