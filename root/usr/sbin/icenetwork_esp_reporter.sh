#!/bin/sh

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

STATUS_DIR='/var/run/icenetwork_esp'
STATUS_FILE="$STATUS_DIR/status.json"

ensure_uint() {
    local value="$1"
    local fallback="$2"

    case "$value" in
        ''|*[!0-9]*)
            echo "$fallback"
            ;;
        *)
            echo "$value"
            ;;
    esac
}

sanitize_header_token() {
    printf '%s' "$1" | tr -d '\r\n'
}

compute_hmac_sha256() {
    local payload="$1"
    local secret="$2"
    local signature=''

    if command -v openssl >/dev/null 2>&1; then
        signature="$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" 2>/dev/null | awk '{print $NF}')"
    fi

    printf '%s' "$signature"
}

load_settings() {
    config_load icenetwork_esp

    config_get ENABLED main enabled '1'
    config_get ESP_SERVER main server '192.168.1.2'
    config_get ESP_PORT main port '9000'
    config_get ESP_PATH main esp_path '/metrics'
    config_get AUTH_MODE main auth_mode 'none'
    config_get AUTH_TOKEN main auth_token ''
    config_get AUTH_HEADER_NAME main auth_header_name 'X-Auth-Token'
    config_get HMAC_SECRET main hmac_secret ''
    config_get HMAC_HEADER_NAME main hmac_header_name 'X-Signature'
    config_get HMAC_TIMESTAMP_HEADER main hmac_timestamp_header 'X-Timestamp'
    config_get CHECK_INTERVAL main check_interval '60'
    config_get PING_TARGET main ping_target '8.8.8.8'
    config_get PING_COUNT main ping_count '4'
    config_get PING_TIMEOUT main ping_timeout '2'
    config_get TIMEOUT_LOSS_THRESHOLD main timeout_loss_threshold '100'
    config_get TIMEOUT_COMMAND main timeout_command ''
    config_get SPEEDTEST_ENABLED main speedtest_enabled '1'
    config_get SPEEDTEST_URL main speedtest_url 'http://speed.cloudflare.com/__down?bytes=5000000'
    config_get SPEEDTEST_TIMEOUT main speedtest_timeout '15'
    config_get SPEEDTEST_INTERVAL main speedtest_interval '300'
    config_get UA3F_AUTOSTART main ua3f_autostart '1'
    config_get UA3F_SERVICE main ua3f_service 'ua3f'

    case "$AUTH_MODE" in
        none|token|hmac) ;;
        *) AUTH_MODE='none' ;;
    esac

    AUTH_TOKEN="$(sanitize_header_token "$AUTH_TOKEN")"
    AUTH_HEADER_NAME="$(sanitize_header_token "$AUTH_HEADER_NAME")"
    [ -z "$AUTH_HEADER_NAME" ] && AUTH_HEADER_NAME='X-Auth-Token'

    HMAC_SECRET="$(sanitize_header_token "$HMAC_SECRET")"
    HMAC_HEADER_NAME="$(sanitize_header_token "$HMAC_HEADER_NAME")"
    [ -z "$HMAC_HEADER_NAME" ] && HMAC_HEADER_NAME='X-Signature'

    HMAC_TIMESTAMP_HEADER="$(sanitize_header_token "$HMAC_TIMESTAMP_HEADER")"
    [ -z "$HMAC_TIMESTAMP_HEADER" ] && HMAC_TIMESTAMP_HEADER='X-Timestamp'

    CHECK_INTERVAL="$(ensure_uint "$CHECK_INTERVAL" 60)"
    [ "$CHECK_INTERVAL" -lt 5 ] && CHECK_INTERVAL=5

    PING_COUNT="$(ensure_uint "$PING_COUNT" 4)"
    [ "$PING_COUNT" -lt 1 ] && PING_COUNT=1
    [ "$PING_COUNT" -gt 10 ] && PING_COUNT=10

    PING_TIMEOUT="$(ensure_uint "$PING_TIMEOUT" 2)"
    [ "$PING_TIMEOUT" -lt 1 ] && PING_TIMEOUT=1
    [ "$PING_TIMEOUT" -gt 30 ] && PING_TIMEOUT=30

    TIMEOUT_LOSS_THRESHOLD="$(ensure_uint "$TIMEOUT_LOSS_THRESHOLD" 100)"
    [ "$TIMEOUT_LOSS_THRESHOLD" -lt 1 ] && TIMEOUT_LOSS_THRESHOLD=1
    [ "$TIMEOUT_LOSS_THRESHOLD" -gt 100 ] && TIMEOUT_LOSS_THRESHOLD=100

    SPEEDTEST_TIMEOUT="$(ensure_uint "$SPEEDTEST_TIMEOUT" 15)"
    [ "$SPEEDTEST_TIMEOUT" -lt 3 ] && SPEEDTEST_TIMEOUT=3

    SPEEDTEST_INTERVAL="$(ensure_uint "$SPEEDTEST_INTERVAL" 300)"
    [ "$SPEEDTEST_INTERVAL" -lt 30 ] && SPEEDTEST_INTERVAL=30

    if [ -z "$ESP_PATH" ]; then
        ESP_PATH='/metrics'
    fi
    case "$ESP_PATH" in
        /*) ;;
        *) ESP_PATH="/$ESP_PATH" ;;
    esac
}

collect_ping_metrics() {
    local ping_output

    ping_output="$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$PING_TARGET" 2>/dev/null || true)"

    PACKET_LOSS="$(printf '%s\n' "$ping_output" | awk -F'[, %]+' '/packet loss/ {print $7; exit}')"
    PACKET_LOSS="$(ensure_uint "$PACKET_LOSS" 100)"

    LATENCY_AVG_MS="$(printf '%s\n' "$ping_output" | awk -F'=' '/min\/avg\/max/ {gsub(/^[[:space:]]+/, "", $2); split($2, v, "/"); print v[2]; exit}')"
    [ -z "$LATENCY_AVG_MS" ] && LATENCY_AVG_MS='0'

    if [ "$PACKET_LOSS" -ge 100 ]; then
        NETWORK_REACHABLE=0
    else
        NETWORK_REACHABLE=1
    fi
}

is_service_running() {
    local service_name="$1"

    if [ -x "/etc/init.d/$service_name" ]; then
        /etc/init.d/$service_name running >/dev/null 2>&1
        return $?
    fi

    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$service_name" >/dev/null 2>&1
        return $?
    fi

    pidof "$service_name" >/dev/null 2>&1
}

check_ua3f() {
    UA3F_RUNNING=0
    UA3F_RESTARTED=0

    if is_service_running "$UA3F_SERVICE"; then
        UA3F_RUNNING=1
        return 0
    fi

    if [ "$UA3F_AUTOSTART" = '1' ] && [ -x "/etc/init.d/$UA3F_SERVICE" ]; then
        /etc/init.d/$UA3F_SERVICE start >/dev/null 2>&1 || true
        UA3F_RESTARTED=1
        if is_service_running "$UA3F_SERVICE"; then
            UA3F_RUNNING=1
        fi
    fi
}

run_speedtest() {
    local now start_ts end_ts duration bytes

    if [ "$SPEEDTEST_ENABLED" != '1' ]; then
        SPEEDTEST_STATUS='disabled'
        SPEED_KBPS=0
        SPEEDTEST_BYTES=0
        SPEEDTEST_SECONDS=0
        return 0
    fi

    now="$(date +%s)"
    if [ "$LAST_SPEEDTEST_TS" -ne 0 ] && [ $((now - LAST_SPEEDTEST_TS)) -lt "$SPEEDTEST_INTERVAL" ]; then
        SPEEDTEST_STATUS="$LAST_SPEEDTEST_STATUS"
        SPEED_KBPS="$LAST_SPEED_KBPS"
        SPEEDTEST_BYTES="$LAST_SPEEDTEST_BYTES"
        SPEEDTEST_SECONDS="$LAST_SPEEDTEST_SECONDS"
        return 0
    fi

    start_ts="$now"
    bytes="$(wget -q -T "$SPEEDTEST_TIMEOUT" -O - "$SPEEDTEST_URL" 2>/dev/null | wc -c | tr -d ' ')"
    end_ts="$(date +%s)"

    duration=$((end_ts - start_ts))
    [ "$duration" -lt 1 ] && duration=1

    bytes="$(ensure_uint "$bytes" 0)"
    if [ "$bytes" -gt 0 ]; then
        SPEED_KBPS=$((bytes * 8 / duration / 1000))
        SPEEDTEST_STATUS='ok'
    else
        SPEED_KBPS=0
        SPEEDTEST_STATUS='failed'
    fi

    SPEEDTEST_BYTES="$bytes"
    SPEEDTEST_SECONDS="$duration"
    LAST_SPEEDTEST_TS="$end_ts"
    LAST_SPEEDTEST_STATUS="$SPEEDTEST_STATUS"
    LAST_SPEED_KBPS="$SPEED_KBPS"
    LAST_SPEEDTEST_BYTES="$SPEEDTEST_BYTES"
    LAST_SPEEDTEST_SECONDS="$SPEEDTEST_SECONDS"
}

run_timeout_action() {
    TIMEOUT_TRIGGERED=0
    TIMEOUT_EXIT_CODE=0

    if [ -z "$TIMEOUT_COMMAND" ]; then
        return 0
    fi

    if [ "$PACKET_LOSS" -lt "$TIMEOUT_LOSS_THRESHOLD" ]; then
        return 0
    fi

    TIMEOUT_TRIGGERED=1
    sh -c "$TIMEOUT_COMMAND" >/dev/null 2>&1
    TIMEOUT_EXIT_CODE="$?"
}

send_to_esp() {
    local payload endpoint timestamp post_ok post_error auth_state
    local hmac_ts hmac_sig

    endpoint="http://$ESP_SERVER:$ESP_PORT$ESP_PATH"
    timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"

    json_init
    json_add_string timestamp "$timestamp"
    json_add_string ping_target "$PING_TARGET"
    json_add_string latency_avg_ms "$LATENCY_AVG_MS"
    json_add_int packet_loss_percent "$PACKET_LOSS"
    json_add_int network_reachable "$NETWORK_REACHABLE"
    json_add_int speed_kbps "$SPEED_KBPS"
    json_add_string speedtest_status "$SPEEDTEST_STATUS"
    json_add_int speedtest_bytes "$SPEEDTEST_BYTES"
    json_add_int speedtest_seconds "$SPEEDTEST_SECONDS"
    json_add_string ua3f_service "$UA3F_SERVICE"
    json_add_int ua3f_running "$UA3F_RUNNING"
    json_add_int ua3f_restarted "$UA3F_RESTARTED"
    json_add_int timeout_triggered "$TIMEOUT_TRIGGERED"
    json_add_int timeout_exit_code "$TIMEOUT_EXIT_CODE"
    payload="$(json_dump)"

    post_ok=0
    post_error='http post failed'
    auth_state="$AUTH_MODE"

    case "$AUTH_MODE" in
        token)
            if [ -z "$AUTH_TOKEN" ]; then
                auth_state='token-missing'
                post_error='token is empty'
            else
                wget -q -T 5 -O /dev/null --header='Content-Type: application/json' --header="$AUTH_HEADER_NAME: $AUTH_TOKEN" --post-data="$payload" "$endpoint" >/dev/null 2>&1 && post_ok=1
            fi
            ;;
        hmac)
            if [ -z "$HMAC_SECRET" ]; then
                auth_state='hmac-missing-secret'
                post_error='hmac secret is empty'
            else
                hmac_ts="$(date +%s)"
                hmac_sig="$(compute_hmac_sha256 "$hmac_ts.$payload" "$HMAC_SECRET")"
                if [ -z "$hmac_sig" ]; then
                    auth_state='hmac-unavailable'
                    post_error='openssl is required for hmac mode'
                else
                    wget -q -T 5 -O /dev/null --header='Content-Type: application/json' --header="$HMAC_HEADER_NAME: $hmac_sig" --header="$HMAC_TIMESTAMP_HEADER: $hmac_ts" --post-data="$payload" "$endpoint" >/dev/null 2>&1 && post_ok=1
                fi
            fi
            ;;
        *)
            auth_state='none'
            wget -q -T 5 -O /dev/null --header='Content-Type: application/json' --post-data="$payload" "$endpoint" >/dev/null 2>&1 && post_ok=1
            ;;
    esac

    if [ "$post_ok" -eq 1 ]; then
        post_error='ok'
    fi

    LAST_POST_OK="$post_ok"
    LAST_POST_ERROR="$post_error"
    LAST_AUTH_STATE="$auth_state"
    LAST_ENDPOINT="$endpoint"
    LAST_REPORT_TS="$timestamp"

    if [ "$post_ok" -ne 1 ]; then
        logger -t icenetwork_esp "failed to post metrics to $endpoint: $post_error"
    fi
}

write_status_file() {
    local dump status_tmp

    mkdir -p "$STATUS_DIR"

    json_init
    json_add_string timestamp "$LAST_REPORT_TS"
    json_add_int enabled "$RUNTIME_ENABLED"
    json_add_string endpoint "$LAST_ENDPOINT"
    json_add_string auth_mode "$AUTH_MODE"
    json_add_string auth_state "$LAST_AUTH_STATE"

    json_add_object metrics
    json_add_string ping_target "$PING_TARGET"
    json_add_string latency_avg_ms "$LATENCY_AVG_MS"
    json_add_int packet_loss_percent "$PACKET_LOSS"
    json_add_int network_reachable "$NETWORK_REACHABLE"
    json_add_int speed_kbps "$SPEED_KBPS"
    json_add_string speedtest_status "$SPEEDTEST_STATUS"
    json_add_int speedtest_bytes "$SPEEDTEST_BYTES"
    json_add_int speedtest_seconds "$SPEEDTEST_SECONDS"
    json_close_object

    json_add_object service
    json_add_string ua3f_service "$UA3F_SERVICE"
    json_add_int ua3f_running "$UA3F_RUNNING"
    json_add_int ua3f_restarted "$UA3F_RESTARTED"
    json_close_object

    json_add_object actions
    json_add_int timeout_triggered "$TIMEOUT_TRIGGERED"
    json_add_int timeout_exit_code "$TIMEOUT_EXIT_CODE"
    json_add_int last_post_ok "$LAST_POST_OK"
    json_add_string last_post_error "$LAST_POST_ERROR"
    json_close_object

    dump="$(json_dump)"
    status_tmp="$STATUS_FILE.tmp"
    printf '%s\n' "$dump" > "$status_tmp" && mv "$status_tmp" "$STATUS_FILE"
}

LAST_SPEEDTEST_TS=0
LAST_SPEEDTEST_STATUS='init'
LAST_SPEED_KBPS=0
LAST_SPEEDTEST_BYTES=0
LAST_SPEEDTEST_SECONDS=0
LAST_POST_OK=0
LAST_POST_ERROR='not started'
LAST_AUTH_STATE='none'
LAST_ENDPOINT=''
LAST_REPORT_TS=''
RUNTIME_ENABLED=0

LATENCY_AVG_MS='0'
PACKET_LOSS=100
NETWORK_REACHABLE=0
SPEED_KBPS=0
SPEEDTEST_STATUS='init'
SPEEDTEST_BYTES=0
SPEEDTEST_SECONDS=0
UA3F_RUNNING=0
UA3F_RESTARTED=0
TIMEOUT_TRIGGERED=0
TIMEOUT_EXIT_CODE=0

while true; do
    load_settings
    LAST_ENDPOINT="http://$ESP_SERVER:$ESP_PORT$ESP_PATH"

    if [ "$ENABLED" != '1' ]; then
        RUNTIME_ENABLED=0
        LAST_REPORT_TS="$(date '+%Y-%m-%dT%H:%M:%S%z')"
        LAST_AUTH_STATE="$AUTH_MODE"
        LAST_POST_OK=0
        LAST_POST_ERROR='service disabled'
        write_status_file
        sleep "$CHECK_INTERVAL"
        continue
    fi

    RUNTIME_ENABLED=1
    collect_ping_metrics
    check_ua3f
    run_speedtest
    run_timeout_action
    send_to_esp
    write_status_file

    sleep "$CHECK_INTERVAL"
done
