#!/usr/bin/env bash
# Vernissage – step 2: set up the instance (runs after ./init.sh).
#
# - creates the administrator through the Vernissage API (like the official installer),
#   confirms the account, grants the administrator role and blocks the temporary
#   "admin" account
# - sets title, contact, registration, image URL, Web Push and optionally SMTP
# - writes a ready-made host Nginx configuration to nginx/<domain>.conf and an
#   overview to INSTALLATION.md

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$ROOT_DIR"

load_env
detect_docker || die "Docker is not reachable – please run ./init.sh first."

printf '%s\n' "${C_BOLD}Vernissage – installation${C_RESET} ($VERNISSAGE_BASEADDRESS)"

if [[ -f "$INSTALLED_MARKER" ]]; then
    warn "This instance has already been installed ($(cat "$INSTALLED_MARKER"))."
    die "Aborting. To start afresh: stop the stack, delete data/, run ./init.sh."
fi

wait_healthy api 600

# Escapes a JSON string (for user input in request bodies).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
}

# POST to the API, directly inside the api container (independent of host Nginx/HTTPS).
# api_post PATH [TOKEN] < body
api_post() {
    local path="$1" token="${2-}"
    compose exec -T -e "VI_TOKEN=$token" -e "VI_PATH=$path" api sh -c '
        if [ -n "$VI_TOKEN" ]; then
            curl --fail-with-body -sS --max-time 20 -X POST \
                -H "Content-Type: application/json" -H "Authorization: Bearer $VI_TOKEN" \
                --data-binary @- "http://127.0.0.1:8080$VI_PATH"
        else
            curl --fail-with-body -sS --max-time 20 -X POST \
                -H "Content-Type: application/json" \
                --data-binary @- "http://127.0.0.1:8080$VI_PATH"
        fi'
}

extract_token() { sed -n -E 's/.*"(accessToken|access_token)" *: *"([^"]+)".*/\2/p'; }

valid_email() { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }

# ---------------------------------------------------------------------------
section "Administrator"

while true; do
    ask ADMIN_USER "Username (letters and digits only)"
    if [[ ! "$ADMIN_USER" =~ ^[A-Za-z0-9]+$ ]]; then warn "Letters and digits only."; continue; fi
    if [[ "$(printf %s "$ADMIN_USER" | tr "[:upper:]" "[:lower:]")" == admin ]]; then warn "'admin' is reserved (the temporary account will be blocked)."; continue; fi
    break
done
while true; do
    ask ADMIN_EMAIL "Email address"
    valid_email "$ADMIN_EMAIL" && break
    warn "Invalid email address."
done
ask ADMIN_NAME "Display name" "$ADMIN_USER"
ask_secret ADMIN_PASSWORD "Password (8–32 characters)" 8 32

# ---------------------------------------------------------------------------
section "Instance"

ask WEB_TITLE "Instance name" "Vernissage"
ask_optional WEB_DESCRIPTION "Short description"
while true; do
    ask WEB_EMAIL "Public contact email" "$ADMIN_EMAIL"
    valid_email "$WEB_EMAIL" && break
    warn "Invalid email address."
done

info "Registration of new users:"
info "  1) closed"
info "  2) subject to approval by moderators"
info "  3) by invitation only"
info "  4) open to everyone"
while true; do
    ask REG_MODE "Choice" "1"
    case "$REG_MODE" in
        1) REG_OPEN=0; REG_APPROVAL=0; REG_INVITE=0 ;;
        2) REG_OPEN=0; REG_APPROVAL=1; REG_INVITE=0 ;;
        3) REG_OPEN=0; REG_APPROVAL=0; REG_INVITE=1 ;;
        4) REG_OPEN=1; REG_APPROVAL=0; REG_INVITE=0 ;;
        *) warn "Please choose 1–4."; continue ;;
    esac
    break
done

# ---------------------------------------------------------------------------
section "Outgoing email (SMTP)"

SMTP_ENABLED=false
if confirm "Configure SMTP now? (can also be done later under /settings)" n; then
    SMTP_ENABLED=true
    ask SMTP_HOST "SMTP server"
    ask SMTP_PORT "SMTP port" "587"
    ask_optional SMTP_USER "SMTP username"
    SMTP_PASSWORD=""
    [[ -n "$SMTP_USER" ]] && ask_secret SMTP_PASSWORD "SMTP password" 1 256
    info "Encryption: none | ssl | startTls | startTlsWhenAvailable"
    while true; do
        ask SMTP_SECURE "Encryption" "startTls"
        [[ "$SMTP_SECURE" =~ ^(none|ssl|startTls|startTlsWhenAvailable)$ ]] && break
        warn "Invalid value."
    done
    ask SMTP_FROM "Sender address" "noreply@$VERNISSAGE_DOMAIN"
    ask SMTP_FROM_NAME "Sender name" "$WEB_TITLE"
fi

# ---------------------------------------------------------------------------
section "Creating the administrator"

info "Signing in with the temporary built-in account…"
login_body="{\"userNameOrEmail\":\"admin\",\"password\":\"admin\"}"
bootstrap_token="$(printf '%s' "$login_body" | api_post /api/v1/account/login | extract_token)" \
    || die "Sign-in with admin/admin failed – has the instance already been set up?"
[[ -n "$bootstrap_token" ]] || die "No access token received for the temporary administrator."
ok "Temporary administrator signed in."

register_body="{\"userName\":$(json_escape "$ADMIN_USER"),\"email\":$(json_escape "$ADMIN_EMAIL"),\"password\":$(json_escape "$ADMIN_PASSWORD"),\"redirectBaseUrl\":$(json_escape "$VERNISSAGE_BASEADDRESS"),\"agreement\":true,\"name\":$(json_escape "$ADMIN_NAME"),\"securityToken\":\"\",\"locale\":\"en_US\"}"
printf '%s' "$register_body" | api_post /api/v1/register "$bootstrap_token" >/dev/null \
    || die "Registering the administrator failed."
ok "Account '$ADMIN_USER' created through the API (including its key pair)."

info "Confirming the account, granting the administrator role, blocking the temporary admin…"
ADMIN_ID="$(psql_exec <<SQL
DO \$vi\$
DECLARE
    target_user_id BIGINT;
    administrator_role_id BIGINT;
BEGIN
    SELECT "id" INTO STRICT target_user_id FROM "Users" WHERE "userName" = $(sql_quote "$ADMIN_USER");
    SELECT "id" INTO STRICT administrator_role_id FROM "Roles" WHERE "code" = 'administrator';

    UPDATE "Users" SET "emailWasConfirmed" = TRUE, "isApproved" = TRUE WHERE "id" = target_user_id;

    IF NOT EXISTS (SELECT 1 FROM "UserRoles" WHERE "userId" = target_user_id AND "roleId" = administrator_role_id) THEN
        INSERT INTO "UserRoles" ("id", "userId", "roleId", "createdAt")
        VALUES (7669802715723076318, target_user_id, administrator_role_id, CURRENT_TIMESTAMP);
    END IF;

    UPDATE "Users" SET "isBlocked" = TRUE WHERE "userName" = 'admin';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Temporary admin account not found.';
    END IF;
END
\$vi\$;
SELECT "id" FROM "Users" WHERE "userName" = $(sql_quote "$ADMIN_USER");
SQL
)"
ADMIN_ID="$(printf '%s' "$ADMIN_ID" | tr -dc '0-9')"
[[ -n "$ADMIN_ID" ]] || die "Could not determine the ID of the new administrator."
ok "Administrator active (ID $ADMIN_ID), temporary account 'admin' blocked."

# ---------------------------------------------------------------------------
section "Settings"

set_setting() { printf 'UPDATE "Settings" SET "value" = %s, "updatedAt" = CURRENT_TIMESTAMP WHERE "key" = %s;\n' "$(sql_quote "$2")" "$(sql_quote "$1")"; }

{
    echo "BEGIN;"
    set_setting systemDefaultUserId "$ADMIN_ID"
    set_setting webContactUserId "$ADMIN_ID"
    set_setting webTitle "$WEB_TITLE"
    [[ -n "$WEB_DESCRIPTION" ]] && set_setting webDescription "$WEB_DESCRIPTION"
    set_setting webEmail "$WEB_EMAIL"
    set_setting isRegistrationOpened "$REG_OPEN"
    set_setting isRegistrationByApprovalOpened "$REG_APPROVAL"
    set_setting isRegistrationByInvitationsOpened "$REG_INVITE"
    set_setting imagesUrl "$VERNISSAGE_BASEADDRESS/static-resource/"
    set_setting webPushEndpoint "http://push:3000/send"
    set_setting webPushSecretKey "$VPUSH_KEY"
    set_setting webPushVapidPublicKey "$WEBPUSH_VAPID_PUBLIC_KEY"
    set_setting webPushVapidPrivateKey "$WEBPUSH_VAPID_PRIVATE_KEY"
    set_setting webPushVapidSubject "mailto:$ADMIN_EMAIL"
    set_setting isWebPushEnabled "1"
    if [[ "$SMTP_ENABLED" == true ]]; then
        set_setting emailHostname "$SMTP_HOST"
        set_setting emailPort "$SMTP_PORT"
        set_setting emailUserName "$SMTP_USER"
        set_setting emailPassword "$SMTP_PASSWORD"
        set_setting emailSecureMethod "$SMTP_SECURE"
        set_setting emailFromAddress "$SMTP_FROM"
        set_setting emailFromName "$SMTP_FROM_NAME"
    fi
    echo "COMMIT;"
} | psql_exec >/dev/null
ok "Instance settings saved."

info "Restarting API and jobs so that the settings are loaded…"
compose_noin restart api jobs >/dev/null
wait_healthy api 300
wait_healthy jobs 300

login_body="{\"userNameOrEmail\":$(json_escape "$ADMIN_USER"),\"password\":$(json_escape "$ADMIN_PASSWORD")}"
login_response="$(printf '%s' "$login_body" | api_post /api/v1/account/login)" \
    || die "Sign-in with the new administrator failed."
if printf '%s' "$login_response" | grep -q '"administrator"'; then
    ok "Sign-in as '$ADMIN_USER' with administrator role verified."
else
    warn "Sign-in works, but the administrator role is not visible in the token – please check under /users."
fi
unset ADMIN_PASSWORD SMTP_PASSWORD login_body register_body login_response bootstrap_token

# ---------------------------------------------------------------------------
section "Host Nginx configuration"

mkdir -p "$NGINX_DIR"
NGINX_CONF="nginx/$VERNISSAGE_DOMAIN.conf"

cat > "$ROOT_DIR/$NGINX_CONF" <<EOF
# Host Nginx template for $VERNISSAGE_DOMAIN – generated by install.sh
#
#   sudo cp $NGINX_CONF /etc/nginx/sites-available/$VERNISSAGE_DOMAIN
#   sudo ln -s /etc/nginx/sites-available/$VERNISSAGE_DOMAIN /etc/nginx/sites-enabled/
#   sudo nginx -t && sudo systemctl reload nginx
#   sudo certbot --nginx -d $VERNISSAGE_DOMAIN

server {
    listen 80;
    listen [::]:80;

    server_name $VERNISSAGE_DOMAIN;

    # Must be >= "Maximum file size" under /settings.
    client_max_body_size $MAX_UPLOAD_SIZE;

    location / {
        proxy_pass http://127.0.0.1:$PROXY_PORT;

        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
}
EOF

cat > "$INSTALLATION_FILE" <<EOF
# Vernissage instance $VERNISSAGE_DOMAIN

Installed on $(date '+%Y-%m-%d %H:%M %Z').

| | |
|---|---|
| URL | $VERNISSAGE_BASEADDRESS |
| Internal proxy | http://$PROXY_BIND:$PROXY_PORT |
| Compose project | $COMPOSE_PROJECT_NAME |
| Administrator | $ADMIN_USER ($ADMIN_EMAIL) |
| Images | $VERNISSAGE_BASEADDRESS/static-resource/ (MinIO bucket \`$S3_BUCKET\`) |
| Web Push | enabled |
| SMTP | $([[ "$SMTP_ENABLED" == true ]] && echo "$SMTP_HOST:$SMTP_PORT" || echo "not configured – set it up under /settings") |

All passwords and keys are kept in \`.env.local\` (not here).

## Next steps

1. Add \`$NGINX_CONF\` to the host Nginx (the commands are in the file).
2. \`sudo certbot --nginx -d $VERNISSAGE_DOMAIN\`
3. Open $VERNISSAGE_BASEADDRESS and sign in as \`$ADMIN_USER\`.
4. Review description, rules, privacy policy and, if needed, SMTP under /settings.
5. Set up backups: \`./backup.sh\` (e.g. via cron) and copy them off the server.
EOF

date '+%Y-%m-%d %H:%M %Z' > "$INSTALLED_MARKER"
ok "$NGINX_CONF and INSTALLATION.md written."

# ---------------------------------------------------------------------------
section "Done"

cat <<EOF
Vernissage is running locally on http://127.0.0.1:$PROXY_PORT

Remaining steps on the host:
  sudo cp $NGINX_CONF /etc/nginx/sites-available/$VERNISSAGE_DOMAIN
  sudo ln -s /etc/nginx/sites-available/$VERNISSAGE_DOMAIN /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx
  sudo certbot --nginx -d $VERNISSAGE_DOMAIN

Then: $VERNISSAGE_BASEADDRESS  →  sign in as '$ADMIN_USER'
EOF
