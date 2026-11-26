# Zabbix Proxy Auto Deploy

Interaktywny instalator aktywnego Zabbix Proxy **7.0.32 LTS**, Agenta 2 i MariaDB dla **Debiana 13 amd64** z systemd.

## Uruchomienie

Na docelowej maszynie pobierz [install-zabbix-proxy.sh](7.0/install-zabbix-proxy.sh) z tego repozytorium. Najpierw sprawdź plan:

```bash
bash install-zabbix-proxy.sh --dry-run
```

Tryb testowy sprawdza wymagania i zainstalowane pakiety oraz zbiera ustawienia. Nie instaluje pakietów, nie zapisuje konfiguracji i nie uruchamia usług. Właściwą instalację wykonaj jako `root`:

```bash
bash install-zabbix-proxy.sh
```

Instalator pokazuje brakujące pakiety i prosi o zgodę na ich instalację. Podaj IPv4 serwera Zabbix, nazwę proxy, nazwę agenta oraz tożsamość PSK. Domyślna tożsamość to `proxy-<nazwa-proxy>`, o ile mieści się w limicie długości.

## Po instalacji

1. W panelu Zabbix dodaj aktywne proxy pod nazwą z podsumowania.
2. Włącz PSK dla połączeń **od proxy**. Wpisz podane w podsumowaniu tożsamość i klucz PSK. Klucz jest też dostępny w `/etc/zabbix/proxy.psk`. Uruchamiaj instalację w zaufanym terminalu, ponieważ podsumowanie zawiera sekret.
3. Sprawdź stan usług i potwierdź w panelu Zabbix, że proxy nawiązało połączenie.

```bash
systemctl is-active mariadb zabbix-proxy zabbix-agent2
journalctl -u zabbix-proxy -n 50 --no-pager
```

Proxy potrzebuje połączenia wychodzącego do serwera na TCP/10051. Podany w podsumowaniu adres IPv4 proxy jest lokalnym adresem źródłowym na trasie do serwera. W konfiguracji Agenta 2 instalator ustawia wyłącznie `Hostname`.

Instalator jest przeznaczony do nowego wdrożenia. Jeśli baza `zabbix_proxy`, użytkownik `zabbix@localhost` lub plik PSK już istnieją, przed kolejną próbą sprawdź stan maszyny. Kopie konfiguracji są zapisywane w katalogu `/etc/zabbix/proxy-install-backup.*`.

[Szczegóły instalatora](SPECIFICATION.md) · [Historia zmian](CHANGELOG.md) · [Licencja MIT](LICENSE)

[Dokumentacja Zabbix 7.0 — szyfrowanie aktywnego proxy](https://www.zabbix.com/documentation/7.0/en/manual/encryption/using_pre_shared_keys#configuring-psk-for-server---active-proxy-communication-example)
