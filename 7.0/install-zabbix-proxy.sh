#!/usr/bin/env bash
# Samodzielny instalator Zabbix Proxy 7.0.32 na Debianie 13 (amd64).
set +x
set -Eeuo pipefail
umask 077

# Zapewnij narzędziom APT i dpkg dostęp do poleceń systemowych.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin

readonly zabbix_version=7.0.32
readonly release_version=1:7.0-5+debian13
readonly repo=https://repo.zabbix.com/zabbix/7.0/debian
readonly proxy_config=/etc/zabbix/zabbix_proxy.conf
readonly agent_config=/etc/zabbix/zabbix_agent2.conf
readonly psk_file=/etc/zabbix/proxy.psk
readonly schema=/usr/share/zabbix-sql-scripts/mysql/proxy.sql
readonly -a zabbix_packages=(zabbix-proxy-mysql zabbix-agent2 zabbix-sql-scripts)
rr
fail() {
    printf 'Błąd: %s\n' "$*" >&2
    exit 1
}

installed_version() {
    local record
    record=$(dpkg-query -W -f='${db:Status-Status} ${Version}' "$1" 2>/dev/null) || return 1
    [[ $record == 'installed '* ]] || return 1
    printf '%s\n' "${record#installed }"
}

valid_ipv4() {
    local value=$1 octet
    local -a octets
    [[ $value =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$value"
    for octet in "${octets[@]}"; do
        [[ $octet == 0 || $octet != 0* ]] && (( 10#$octet <= 255 )) || return 1
    done
}

read_name() {
    local label=$1 default=$2
    while :; do
        read -r -p "$label [$default]: " name_input || fail 'Przerwano wprowadzanie danych.'
        name_input=${name_input:-$default}
        [[ $name_input =~ ^[A-Za-z0-9_.-]{1,128}$ ]] && return
        printf 'Podaj od 1 do 128 znaków: litery ASCII, cyfry, kropka, podkreślenie lub myślnik.\n' >&2
    done
}

dry_run=0
(( $# <= 1 )) || fail 'Użyj --help, aby sprawdzić sposób uruchomienia.'
case "${1:-}" in
    --help|-h)
        printf 'Użycie: bash install-zabbix-proxy.sh [--dry-run]\n'
        printf 'Instalację uruchom jako root na Debianie 13 (amd64) z systemd.\n'
        printf 'Opcja --dry-run sprawdza wymagania i pokazuje plan bez wprowadzania zmian.\n'
        exit 0
        ;;
    --dry-run) dry_run=1 ;;
    '') ;;
    *) fail 'Użyj --help, aby sprawdzić sposób uruchomienia.' ;;
esac
(( dry_run || EUID == 0 )) || fail 'Uruchom skrypt na koncie root.'
[[ -r /etc/os-release ]] || fail 'Nie można rozpoznać systemu.'
# shellcheck source=/dev/null
source /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] || fail 'Wymagany jest Debian 13.'
[[ -d /run/systemd/system ]] || fail 'Wymagany jest działający systemd.'

[[ $(dpkg --print-architecture) == amd64 ]] || fail 'Wymagana jest architektura amd64.'

if (( ! dry_run )); then
    exec 9>/run/lock/install-zabbix-proxy.lock
    flock -n 9 || fail 'Inna instancja instalatora jest już uruchomiona.'
fi
[[ ! -e $psk_file && ! -L $psk_file ]] || fail "Istnieje już $psk_file. Ten skrypt służy do nowej instalacji."
for service in zabbix-proxy zabbix-agent zabbix-server; do
    if systemctl is-active --quiet "$service"; then
        fail "Działa już usługa $service. Nowa instalacja mogłaby z nią kolidować."
    fi
done

missing=()
for package in ca-certificates curl iproute2 openssl mariadb-server mariadb-client zabbix-release "${zabbix_packages[@]}"; do
    if ! version=$(installed_version "$package"); then
        missing+=("$package")
    elif [[ $package == zabbix-release && ! ${version#*:} =~ ^7\.0-.*\+debian13$ ]]; then
        fail "Zainstalowano niezgodny pakiet $package ($version). Sprawdź konfigurację repozytoriów."
    elif [[ $package == zabbix-* && $package != zabbix-release &&
            ${version#*:} != "$zabbix_version"-*+debian13 ]]; then
        fail "Zainstalowano $package w wersji $version. Skrypt wymaga $zabbix_version dla Debiana 13."
    fi
done

if (( ${#missing[@]} )); then
    printf 'Brakujące pakiety wymagane bezpośrednio przez instalator:\n'
    printf '  - %s\n' "${missing[@]}"
    printf 'APT może dobrać dodatkowe zależności.\n'
    if (( ! dry_run )); then
        read -r -p 'Czy zainstalować pakiety? [t/N] ' answer || exit 1
        case "$answer" in
            t|T|tak|Tak|TAK) ;;
            *) printf 'Anulowano instalację.\n'; exit 0 ;;
        esac
    fi
else
    printf 'Wszystkie wymagane pakiety są zainstalowane.\n'
fi

while :; do
    read -r -p 'Adres IPv4 serwera Zabbix: ' server_ip || fail 'Przerwano wprowadzanie danych.'
    valid_ipv4 "$server_ip" && break
    printf 'Podaj poprawny adres IPv4.\n' >&2
done
read_name 'Hostname aktywnego proxy' "$(hostname)"
proxy_name=$name_input
read_name 'Hostname agenta' "$(hostname)"
agent_name=$name_input
default_psk_identity="proxy-$proxy_name"
if (( ${#default_psk_identity} > 127 )); then
    default_psk_identity=
fi
while :; do
    IFS= read -r -p "Tożsamość PSK${default_psk_identity:+ [$default_psk_identity]}: " psk_identity ||
        fail 'Przerwano wprowadzanie danych.'
    psk_identity=${psk_identity:-$default_psk_identity}
    if [[ $psk_identity =~ ^[A-Za-z0-9_.\ -]{1,127}$ &&
          $psk_identity != ' '* && $psk_identity != *' ' ]]; then
        break
    fi
    printf 'Podaj od 1 do 127 znaków: litery ASCII, cyfry, kropki, podkreślenia, myślniki lub spacje wewnątrz nazwy.\n' >&2
done

if (( dry_run )); then
    printf '\nTryb testowy. Plan instalacji\n'
    printf '  Zabbix %s, Debian 13 amd64\n' "$zabbix_version"
    printf '  Serwer Zabbix: %s\n' "$server_ip"
    printf '  Aktywne proxy: %s, tożsamość PSK: %s\n' "$proxy_name" "$psk_identity"
    printf '  Agent 2: %s\n' "$agent_name"
    printf '  MariaDB: sprawdzenie dostępu root przez lokalny socket, utworzenie bazy zabbix_proxy i import schematu\n'
    printf '  Wygenerowanie hasła bazy i klucza w %s\n' "$psk_file"
    printf '  Usługi do uruchomienia i włączenia: mariadb, zabbix-proxy, zabbix-agent2\n'
    exit 0
fi

stage='przygotowanie instalacji'
work_dir=$(mktemp -d)
proxy_stage=
agent_stage=
psk_stage=
restore_binlog=
database_started=0
db_admin=(mariadb --no-defaults --protocol=socket --user=root --batch --skip-column-names)

cleanup() {
    local status=$?
    if [[ -n $restore_binlog ]] &&
        ! "${db_admin[@]}" --execute="SET GLOBAL log_bin_trust_function_creators = $restore_binlog"; then
        printf 'Błąd: przywróć ręcznie log_bin_trust_function_creators do %s.\n' "$restore_binlog" >&2
        status=1
    fi
    if (( status != 0 && database_started )) && [[ -f $proxy_stage ]]; then
        # Zachowaj dane dostępowe, jeśli MariaDB mogła już utworzyć konto.
        if ! cp -- "$proxy_stage" "$backup_dir/zabbix_proxy.pending.conf"; then
            printf 'Konfiguracja do odzyskania: %s\n' "$proxy_stage" >&2
            proxy_stage=
        else
            printf 'Konfiguracja do odzyskania: %s/zabbix_proxy.pending.conf\n' "$backup_dir" >&2
        fi
    fi
    rm -f -- "$work_dir/client.cnf" "$work_dir/zabbix-release.deb" "$work_dir/database-setup.log"
    rmdir -- "$work_dir"
    local staged_file
    for staged_file in "$proxy_stage" "$agent_stage" "$psk_stage"; do
        [[ -z $staged_file ]] || rm -f -- "$staged_file"
    done
    if (( status != 0 )); then
        printf 'Przerwano na etapie „%s” (kod %s).\n' "$stage" "$status" >&2
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if (( ${#missing[@]} )); then
    stage='instalacja pakietów'
    apt-get update
    base_packages=()
    for package in "${missing[@]}"; do
        [[ $package == zabbix-* ]] || base_packages+=("$package")
    done
    if (( ${#base_packages[@]} )); then
        apt-get install -y --no-remove "${base_packages[@]}"
    fi

    if ! installed_version zabbix-release >/dev/null; then
        release_deb="$work_dir/zabbix-release.deb"
        curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
            --output "$release_deb" "$repo/pool/main/z/zabbix-release/zabbix-release_${release_version#*:}_all.deb"
        [[ $(dpkg-deb -f "$release_deb" Package) == zabbix-release &&
           $(dpkg-deb -f "$release_deb" Version) == "$release_version" ]] ||
            fail 'Pobrany pakiet repozytorium ma nieoczekiwane metadane.'
        dpkg -i "$release_deb"
        apt-get update
    fi

    apt_packages=()
    for package in "${zabbix_packages[@]}"; do
        installed_version "$package" >/dev/null && continue
        version=$(apt-cache madison "$package" | awk -F '|' -v repo="$repo" -v wanted="$zabbix_version" '
            {
                gsub(/[[:space:]]/, "", $2)
                version = $2
                sub(/^[0-9]+:/, "", version)
                source = $3
                sub(/^[[:space:]]+/, "", source)
                split(source, fields, /[[:space:]]+/)
                sub(/\/$/, "", fields[1])
                if (!found && fields[1] == repo && index(version, wanted "-") == 1 &&
                    version ~ /\+debian13$/) {
                    print $2
                    found = 1
                }
            }')
        [[ -n $version ]] || fail "Brak pakietu $package w wersji $zabbix_version w oficjalnym repozytorium."
        apt_packages+=("$package=$version")
    done
    if (( ${#apt_packages[@]} )); then
        apt-get install -y --no-remove "${apt_packages[@]}"
    fi
fi

stage='sprawdzanie konfiguracji i MariaDB'
for config in "$proxy_config" "$agent_config"; do
    [[ -f $config && ! -L $config ]] || fail "Oczekiwano zwykłego pliku $config."
done
[[ -r $schema ]] || fail "Brak schematu $schema."
systemctl start mariadb
if ! collisions=$("${db_admin[@]}" --execute="
    SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'zabbix_proxy';
    SELECT User FROM mysql.user WHERE User = 'zabbix' AND Host = 'localhost';"); then
    fail 'MariaDB wymaga dostępu administracyjnego root przez lokalny socket.'
fi
[[ -z $collisions ]] || fail 'Baza zabbix_proxy lub konto zabbix@localhost już istnieje. Sprawdź stan bazy przed ponowną próbą.'

stage='przygotowanie konfiguracji i sekretów'
db_password=$(openssl rand -hex 32)
backup_dir=$(mktemp -d /etc/zabbix/proxy-install-backup.XXXXXXXX)
cp -p -- "$proxy_config" "$agent_config" "$backup_dir/"
proxy_stage=$(mktemp /etc/zabbix/.proxy-conf.XXXXXXXX)
agent_stage=$(mktemp /etc/zabbix/.agent-conf.XXXXXXXX)
psk_stage=$(mktemp /etc/zabbix/.proxy-psk.XXXXXXXX)

{
    sed -E '/^[[:space:]]*(ProxyMode|Server|Hostname|DBHost|DBName|DBUser|DBPassword|TLSConnect|TLSAccept|TLSPSKIdentity|TLSPSKFile)[[:space:]]*=/d' "$proxy_config"
    printf '\nProxyMode=0\nServer=%s\nHostname=%s\n' "$server_ip" "$proxy_name"
    printf 'DBHost=localhost\nDBName=zabbix_proxy\nDBUser=zabbix\nDBPassword=%s\n' "$db_password"
    printf 'TLSConnect=psk\nTLSPSKIdentity=%s\nTLSPSKFile=%s\n' "$psk_identity" "$psk_file"
} > "$proxy_stage"
{
    sed -E '/^[[:space:]]*Hostname[[:space:]]*=/d' "$agent_config"
    printf '\nHostname=%s\n' "$agent_name"
} > "$agent_stage"
openssl rand -hex 32 > "$psk_stage"
chown root:zabbix "$proxy_stage" "$psk_stage"
chmod 0640 "$proxy_stage" "$psk_stage"
chown --reference="$agent_config" "$agent_stage"
chmod --reference="$agent_config" "$agent_stage"
printf '[client]\nuser=zabbix\npassword=%s\nprotocol=socket\n' "$db_password" > "$work_dir/client.cnf"

stage='inicjalizacja bazy danych'
database_started=1
if ! "${db_admin[@]}" > "$work_dir/database-setup.log" 2>&1 <<SQL
CREATE DATABASE zabbix_proxy CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON zabbix_proxy.* TO 'zabbix'@'localhost';
SQL
then
    fail 'Nie udało się utworzyć bazy lub użytkownika. Sprawdź stan obiektów i uprawnienia MariaDB.'
fi
rm -f -- "$work_dir/database-setup.log"
unset db_password
binlog_state=$("${db_admin[@]}" --execute='SELECT @@GLOBAL.log_bin, @@GLOBAL.log_bin_trust_function_creators')
if [[ $binlog_state == $'1\t0' ]]; then
    restore_binlog=0
    "${db_admin[@]}" --execute='SET GLOBAL log_bin_trust_function_creators = 1'
fi
stage='import schematu proxy'
mariadb --defaults-file="$work_dir/client.cnf" --default-character-set=utf8mb4 zabbix_proxy < "$schema"
if [[ -n $restore_binlog ]]; then
    "${db_admin[@]}" --execute="SET GLOBAL log_bin_trust_function_creators = $restore_binlog"
    restore_binlog=
fi
rm -f -- "$work_dir/client.cnf"

stage='weryfikacja konfiguracji i uruchomienie usług'
ln -T -- "$psk_stage" "$psk_file"
zabbix_proxy -T -c "$proxy_stage"
zabbix_agent2 -T -c "$agent_stage"
mv -fT -- "$proxy_stage" "$proxy_config"
mv -fT -- "$agent_stage" "$agent_config"
systemctl restart zabbix-proxy zabbix-agent2
for service in mariadb zabbix-proxy zabbix-agent2; do
    systemctl is-active --quiet "$service" || fail "Usługa $service nie działa. Sprawdź journalctl -u $service."
done
systemctl enable mariadb zabbix-proxy zabbix-agent2

proxy_ip=$(ip -4 -o route get "$server_ip" 2>/dev/null |
    awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }') || proxy_ip=
proxy_ip=${proxy_ip:-nie wykryto}

printf '\nUsługi MariaDB, Zabbix Proxy i Zabbix Agent 2 działają.\n'
printf 'Kopie konfiguracji: %s\n' "$backup_dir"
printf 'W panelu Zabbix dodaj aktywne proxy i włącz PSK dla połączeń od proxy.\n'
printf 'Plik klucza PSK: %s\n' "$psk_file"

printf '\nNazwa proxy: %s\n' "$proxy_name"
printf 'Adres IPv4 proxy: %s\n' "$proxy_ip"
printf 'Tożsamość PSK: %s\n' "$psk_identity"
printf 'PSK: '
cat -- "$psk_file"
printf 'Hostname agenta: %s\n' "$agent_name"
