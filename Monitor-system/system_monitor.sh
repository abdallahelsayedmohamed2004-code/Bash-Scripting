#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Linux System Monitor & Telegram Alert Bot
# Periodically checks CPU, memory, and root filesystem usage.
# Critical readings are sent to Telegram; all readings are written to a log.
# -----------------------------------------------------------------------------

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Load optional local configuration. Keep .env out of version control.
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
fi

WARNING_THRESHOLD="${WARNING_THRESHOLD:-70}"
CRITICAL_THRESHOLD="${CRITICAL_THRESHOLD:-90}"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/system_monitor.log}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

log_message() {
    local level="$1"
    local message="$2"
    local timestamp

    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}" | tee -a "${LOG_FILE}"
}

validate_configuration() {
    if [[ ! "${WARNING_THRESHOLD}" =~ ^(0|[1-9][0-9]*)$ ]] ||
       [[ ! "${CRITICAL_THRESHOLD}" =~ ^(0|[1-9][0-9]*)$ ]]; then
        printf 'ERROR: Thresholds must be integer percentages from 0 to 100.\n' >&2
        exit 1
    fi

    if (( WARNING_THRESHOLD < 0 || WARNING_THRESHOLD > 100 ||
          CRITICAL_THRESHOLD < 0 || CRITICAL_THRESHOLD > 100 )); then
        printf 'ERROR: Thresholds must be between 0 and 100.\n' >&2
        exit 1
    fi

    if (( WARNING_THRESHOLD >= CRITICAL_THRESHOLD )); then
        printf 'ERROR: WARNING_THRESHOLD must be lower than CRITICAL_THRESHOLD.\n' >&2
        exit 1
    fi

    local required_command
    for required_command in awk date df free hostname sleep tee; do
        if ! command -v "${required_command}" >/dev/null 2>&1; then
            printf 'ERROR: Required command not found: %s\n' "${required_command}" >&2
            exit 1
        fi
    done

    mkdir -p -- "$(dirname -- "${LOG_FILE}")"
    if ! touch "${LOG_FILE}"; then
        printf 'ERROR: Cannot write to log file: %s\n' "${LOG_FILE}" >&2
        exit 1
    fi
}

# Read aggregate CPU counters from /proc/stat.
# The total includes user, nice, system, idle, iowait, irq, softirq and steal.
read_cpu_counters() {
    awk '
        /^cpu / {
            total = $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9
            idle = $5 + $6
            printf "%.0f %.0f\n", total, idle
            found = 1
            exit
        }
        END {
            if (!found) exit 1
        }
    ' /proc/stat
}

get_cpu_usage() {
    local total_1 idle_1 total_2 idle_2 total_delta idle_delta

    read -r total_1 idle_1 < <(read_cpu_counters)
    sleep 1
    read -r total_2 idle_2 < <(read_cpu_counters)

    total_delta=$((total_2 - total_1))
    idle_delta=$((idle_2 - idle_1))

    if (( total_delta <= 0 )); then
        printf '0\n'
        return
    fi

    awk -v total="${total_delta}" -v idle="${idle_delta}" \
        'BEGIN { usage = 100 * (total - idle) / total; printf "%.0f\n", usage }'
}

# Use MemAvailable when calculating used memory so reclaimable cache is
# not treated as fully consumed application memory.
get_ram_usage() {
    free -b | awk '
        /^Mem:/ {
            if ($2 <= 0 || NF < 7) exit 1
            used = $2 - $7
            usage = (used / $2) * 100
            printf "%.0f\n", usage
            found = 1
            exit
        }
        END {
            if (!found) exit 1
        }
    '
}

# This lab monitors the filesystem containing /, not every mounted filesystem.
get_disk_usage() {
    df -P / | awk '
        NR == 2 {
            gsub(/%/, "", $5)
            print $5
            found = 1
            exit
        }
        END {
            if (!found) exit 1
        }
    '
}

send_telegram_alert() {
    local resource="$1"
    local usage="$2"
    local message

    if [[ -z "${TELEGRAM_BOT_TOKEN}" || -z "${TELEGRAM_CHAT_ID}" ]]; then
        log_message "ERROR" "Telegram is not configured; critical ${resource} alert was not sent."
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_message "ERROR" "curl is not installed; Telegram alert could not be sent."
        return 0
    fi

    message="$(printf 'CRITICAL ALERT\nHost: %s\nResource: %s\nCurrent usage: %s%%\nCritical threshold: %s%%' \
        "$(hostname)" "${resource}" "${usage}" "${CRITICAL_THRESHOLD}")"

    # --data-urlencode safely encodes spaces and line breaks in the message.
    # Suppress curl diagnostics here to avoid accidentally logging the token
    # embedded in the Bot API URL. The event itself is still recorded below.
    if curl --silent --show-error --fail \
        --connect-timeout 10 --max-time 20 \
        --request POST \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        >/dev/null 2>&1; then
        log_message "INFO" "Telegram critical alert delivered for ${resource}."
    else
        log_message "ERROR" "Telegram request failed for ${resource}; check bot token, chat ID, and network connectivity."
    fi
}

check_metric() {
    local resource_name="$1"
    local usage_value="$2"

    if [[ ! "${usage_value}" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid ${resource_name} metric received: ${usage_value}"
        return 1
    fi

    if (( usage_value >= CRITICAL_THRESHOLD )); then
        log_message "CRITICAL" "${resource_name} usage is ${usage_value}% (critical threshold: ${CRITICAL_THRESHOLD}%)."
        send_telegram_alert "${resource_name}" "${usage_value}"
    elif (( usage_value >= WARNING_THRESHOLD )); then
        log_message "WARNING" "${resource_name} usage is ${usage_value}% (warning threshold: ${WARNING_THRESHOLD}%)."
    else
        log_message "INFO" "${resource_name} usage is normal at ${usage_value}%."
    fi
}

main() {
    validate_configuration

    log_message "INFO" "----- Starting system resource check -----"

    local disk_usage ram_usage cpu_usage
    disk_usage="$(get_disk_usage)"
    ram_usage="$(get_ram_usage)"
    cpu_usage="$(get_cpu_usage)"

    check_metric "Disk" "${disk_usage}"
    check_metric "RAM" "${ram_usage}"
    check_metric "CPU" "${cpu_usage}"

    log_message "INFO" "----- Resource check completed -----"
}

main "$@"
