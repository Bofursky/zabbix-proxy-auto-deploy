# Specyfikacja instalatora Zabbix Proxy

## Platforma i pakiety

- Debian 13, `amd64`, systemd. Instalacja wymaga konta `root`.
- Skrypt znajduje się w repozytorium pod ścieżką `7.0/install-zabbix-proxy.sh`, działa samodzielnie i ustawia systemowy `PATH`.
- Brakujące pakiety są wyświetlane przed instalacją i wymagają potwierdzenia.
- Brakujący pakiet repozytorium `zabbix-release` jest pobierany w wersji `1:7.0-5+debian13`. Skrypt sprawdza nazwę i wersję w metadanych pakietu. Zgodna już zainstalowana wersja repozytorium może zostać użyta ponownie.
- `zabbix-proxy-mysql`, `zabbix-agent2` i `zabbix-sql-scripts` są przypięte do linii wydania `7.0.32` dla Debiana 13. MariaDB i narzędzia pomocnicze pochodzą z APT.

## Konfiguracja

- Proxy działa w trybie aktywnym i łączy się z podanym IPv4 serwera Zabbix. Używa `TLSConnect=psk`.
- Instalator przyjmuje osobne nazwy proxy i agenta. Tożsamość PSK użytkownik może podać ręcznie. Dopuszczalne jest od 1 do 127 znaków ASCII z zestawu pokazanego przez instalator.
- Skrypt generuje oddzielne losowe hasło bazy i 256-bitowy klucz PSK. Hasło trafia do `/etc/zabbix/zabbix_proxy.conf`, a klucz do `/etc/zabbix/proxy.psk`. Oba pliki mają uprawnienia `0640` i właściciela `root:zabbix`.
- MariaDB jest konfigurowana przez lokalny socket z konta administracyjnego `root`. Powstaje baza `zabbix_proxy` z `utf8mb4_bin` i konto `zabbix@localhost` z uprawnieniami do tej bazy. Schemat jest importowany jako użytkownik bazy. Jeżeli import wymaga tymczasowego włączenia `log_bin_trust_function_creators`, skrypt przywraca poprzednią wartość.
- Skrypt archiwizuje konfiguracje proxy i agenta, aktualizuje w Agencie 2 wyłącznie `Hostname`, sprawdza konfiguracje przez `-T` oraz sprawdza i włącza usługi systemd.

## Wynik i ograniczenia

Po udanej instalacji skrypt kończy podsumowanie polami w kolejności: nazwa proxy, lokalny adres IPv4 na trasie do serwera, tożsamość PSK, pełny klucz PSK i hostname agenta. Brak adresu źródłowego jest zgłaszany jako `nie wykryto`.

`--dry-run` pokazuje plan na podstawie odczytów lokalnych i wprowadzonych danych. Dostęp do bazy, import oraz uruchomienie usług są sprawdzane podczas właściwej instalacji. Skrypt przerywa przy wykryciu istniejącej bazy, konta lub klucza. Po błędzie w trakcie wdrożenia administrator sprawdza stan przed ponowieniem.
