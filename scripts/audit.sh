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

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Синтаксис конфигурации Nginx" "0" "$(sudo nginx -t >&2; echo $?)"
check "Срок действия сертификата" "0" "$(openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "${CERT_MIN_SECONDS:-2592000}" >/dev/null; echo $?)"
check "Права файлов сайта и закрытого ключа" "0::600" "$(paths=$(find /var/www/devops-site -perm -o+w); printf '%s:%s:' "$?" "$paths"; sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "[5] Контейнеризация"
check "Служба Docker активна" "active" "$(systemctl is-active docker)"
db_health=$(sudo docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null) || db_health="недоступен"
check "Контейнер PostgreSQL готов" "healthy" "$db_health"
if sockets=$(ss -H -tln); then
    public_ports=$(awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:/ {print $4}' <<< "$sockets")
else
    public_ports="не удалось прочитать список сокетов"
fi
check "Порты 5000 и 5432 не слушают внешние адреса" "" "$public_ports"
env_mode=$(stat -c '%a' /home/devops/app/.env 2>/dev/null) || env_mode="недоступен"
check "Права файла .env" "600" "$env_mode"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ "$FAIL" -eq 0 ]]
