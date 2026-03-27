/**
 * PM2 ecosystem config — ccproxy-codex (P124)
 * New Codex subscription proxy on port :3462
 */
module.exports = {
  apps: [
    {
      name: 'ccproxy-codex',
      script: '/home/gpu1/ccproxy-codex/.venv/bin/ccproxy',
      interpreter: 'none',
      args: 'serve --config /home/gpu1/ccproxy-codex/config.toml',
      cwd: '/home/gpu1/ccproxy-codex',
      kill_timeout: 950000,
      wait_ready: false,
      listen_timeout: 30000,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 3000,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      out_file: '/home/gpu1/.pm2/logs/ccproxy-codex-out.log',
      error_file: '/home/gpu1/.pm2/logs/ccproxy-codex-error.log',
      merge_logs: true,
      env: {
        PYTHONUNBUFFERED: '1',
      },
    },
  ],
};
