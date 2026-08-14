#!/usr/bin/env node
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

let input = '';
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  try {
    if (!input || !input.trim()) process.exit(0);

    const data = JSON.parse(input);
    const model = data.model?.display_name || 'Claude';
    const rawDir = data.workspace?.current_dir || '';
    const dir = rawDir ? path.basename(rawDir) : 'project';
    const sessionId = data.session_id || 'default';

    const cost = data.cost?.total_cost_usd || 0;
    const pct = Math.floor(data.context_window?.used_percentage || 0);
    const durationMs = data.cost?.total_duration_ms || 0;

    const cyan = '\x1b[36m';
    const green = '\x1b[32m';
    const yellow = '\x1b[33m';
    const red = '\x1b[31m';
    const reset = '\x1b[0m';

    let barColor = green;
    if (pct >= 90) barColor = red;
    else if (pct >= 70) barColor = yellow;

    const filled = Math.min(10, Math.max(0, Math.floor(pct / 10)));
    const empty = 10 - filled;
    const bar = '█'.repeat(filled) + '░'.repeat(empty);

    const mins = Math.floor(durationMs / 60000);
    const secs = Math.floor((durationMs % 60000) / 1000);

    const tmpDir = os.tmpdir();
    const cacheFile = path.join(tmpDir, `statusline-git-cache-${sessionId}.txt`);
    const cacheMaxAgeSeconds = 5;

    let branch = '';
    let staged = 0;
    let modified = 0;

    const cacheIsStale = () => {
      if (!fs.existsSync(cacheFile)) return true;
      try {
        const stats = fs.statSync(cacheFile);
        return (Date.now() - stats.mtimeMs) / 1000 > cacheMaxAgeSeconds;
      } catch (e) {
        return true;
      }
    };

    if (cacheIsStale()) {
      try {
        execSync('git rev-parse --git-dir', { stdio: 'ignore' });
        branch = execSync('git branch --show-current', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
        staged = execSync('git diff --cached --numstat', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim().split('\n').filter(Boolean).length;
        modified = execSync('git diff --numstat', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim().split('\n').filter(Boolean).length;
        fs.writeFileSync(cacheFile, `${branch}|${staged}|${modified}`);
      } catch (e) {
        try { fs.writeFileSync(cacheFile, '||'); } catch (err) {}
      }
    } else {
      try {
        const cachedContent = fs.readFileSync(cacheFile, 'utf8').trim().split('|');
        branch = cachedContent[0] || '';
        staged = parseInt(cachedContent[1] || '0', 10);
        modified = parseInt(cachedContent[2] || '0', 10);
      } catch (e) {}
    }

    const gitStr = branch ? ` | 🌿 ${branch}${staged ? ` +${staged}` : ''}${modified ? ` ~${modified}` : ''}` : '';
    const costFmt = `$${cost.toFixed(2)}`;

    console.log(`${cyan}[${model}]${reset} 📁 ${dir}${gitStr}`);
    console.log(`${barColor}${bar}${reset} ${pct}% | ${yellow}${costFmt}${reset} | ⏱️ ${mins}m ${secs}s`);
  } catch (e) {
    // Prevent unhandled exception from failing status line
  }
});