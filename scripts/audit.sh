#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo " [OK] $desc"
        ((PASS+=1))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL+=1))
    fi
}

sudo -v || exit 1
ssh_config=$(sudo sshd -T) || exit 1
ufw_status=$(sudo env LC_ALL=C ufw status verbose) || exit 1

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" \
    "$(awk '$1 == "permitrootlogin" {print $2}' <<< "$ssh_config")"
check "Парольная аутентификация отключена" "no" \
    "$(awk '$1 == "passwordauthentication" {print $2}' <<< "$ssh_config")"
check "SSH использует нестандартный порт" "yes" \
    "$(awk '$1 == "port" {found=1; if ($2 == 22) standard=1} END {print (found && !standard ? "yes" : "no")}' <<< "$ssh_config")"
check "Максимум три попытки входа" "3" \
    "$(awk '$1 == "maxauthtries" {print $2}' <<< "$ssh_config")"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" \
    "$(awk '$1 == "Status:" {print $2}' <<< "$ufw_status")"
check "Входящий трафик по умолчанию запрещён" "deny" \
    "$(awk '$1 == "Default:" && $3 == "(incoming)," {print $2}' <<< "$ufw_status")"

echo "[3] Учётные записи"
awk -F: '$3 >= 1000 && $3 < 65534 {printf " %s (uid=%s)\n", $1, $3}' /etc/passwd

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ "$FAIL" -eq 0 ]]
