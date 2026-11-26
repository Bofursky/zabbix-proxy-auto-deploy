# AGENTS.md — Zabbix Proxy Auto Deploy

## 1. Cel i zakres projektu

Projekt automatyzuje nowe wdrożenia aktywnego Zabbix Proxy 7.0 LTS, Agenta 2 i MariaDB na Debianie 13 `amd64` z systemd. Instalator to `7.0/install-zabbix-proxy.sh`. Wymagania funkcjonalne opisuje [SPECIFICATION.md](SPECIFICATION.md). Zmiany wersji pakietów, trybu pracy proxy lub zakresu obsługiwanych systemów wymagają osobnego zlecenia.

## 2. Język i styl kodu

Dokumentację, komentarze, komunikaty instalatora i opisy commitów pisz po polsku. Identyfikatory w kodzie i nazwy parametrów Zabbixa zachowuj po angielsku. Pliki Bash zapisuj jako UTF-8 bez BOM z zakończeniami LF. Ogranicz zmiany do zleconego zakresu.

## 3. Zasady zmian w instalatorze

- Zachowuj `--dry-run` jako tryb odczytu i planowania. Instalacja pakietów wymaga potwierdzenia, gdy wykryto braki.
- Weryfikuj wersje pakietów i parametry w oficjalnych źródłach Zabbixa. Zmiany w konfiguracji proxy sprawdzaj pod kątem trybu aktywnego i PSK. W Agencie 2 zachowuj zakres ograniczony do `Hostname`.
- Przy zmianach w instalacji pakietów, konfiguracji lub bazie sprawdzaj scenariusz ponownego uruchomienia po awarii. Istniejącą bazę, konto lub klucz traktuj jako stan wymagający sprawdzenia przez administratora. Zachowuj kopie konfiguracji i przywracaj tymczasowe ustawienia MariaDB po imporcie.
- Zachowuj kolejność ostatnich pięciu pól podsumowania, chyba że użytkownik zleci jej zmianę.

## 4. Bezpieczeństwo i sekrety

Używaj neutralnych danych przykładowych. Pełny PSK wyświetlaj wyłącznie w końcowym podsumowaniu udanej instalacji. Hasło bazy zapisuj w chronionej konfiguracji proxy. Wyjście zawierające sekrety pomijaj w logach, raportach testów, zgłoszeniach i commitach. Operacje destrukcyjne oraz zmiany w środowisku produkcyjnym wymagają wyraźnej zgody.

## 5. Testy

- Dla zmian w Bash uruchom `bash -n`, a przy dostępności narzędzi również ShellCheck i Gitleaks.
- Dobierz scenariusze do zmiany. Dla instalatora sprawdzaj `--dry-run`, odmowę instalacji pakietów, ponowienie po częściowym wdrożeniu i kody zakończenia.
- Pełną instalację, import schematu, uruchomienie usług i połączenie proxy z serwerem sprawdzaj na dedykowanym Debianie 13. Raportuj oddzielnie wyniki symulacji i rzeczywistego wdrożenia.
- GitHub Actions wdrażaj wyłącznie na osobne zlecenie.

## 6. Git i publikacja

Większe zmiany przygotowuj na gałęziach roboczych i preferuj Pull Requesty do `main`. Commity opisuj po polsku zgodnie z Conventional Commits, np. `fix: poprawa wznowienia instalacji proxy`. Przed commitem przedstaw zmienione pliki, wyniki testów i proponowany opis. Commit, push oraz merge do `main` wykonuj po uzyskaniu odpowiedniej zgody. Przed publikacją wskaż repozytorium i gałąź docelową.

## 7. Dokumentacja i raportowanie

[README.md](README.md) opisuje uruchomienie i weryfikację wdrożenia, [SPECIFICATION.md](SPECIFICATION.md) określa wymagania, a [CHANGELOG.md](CHANGELOG.md) rejestruje zmiany widoczne dla użytkownika. Po pracy podaj zakres zmiany, zmienione pliki, wyniki testów i ograniczenia.
