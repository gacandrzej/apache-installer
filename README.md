# Instalacja i Uruchomienie Serwera Apache z SSL i UserDir w Docker Compose

> Ten projekt pozwala na szybkie i łatwe uruchomienie serwera Apache 
> HTTP z obsługą HTTPS (SSL/TLS) oraz modułu UserDir za pomocą Docker Compose. Konfiguracja Apache'a, certyfikaty SSL i katalogi public_html dla użytkowników są zarządzane bezpośrednio na hoście, co ułatwia modyfikację i utrzymanie.

Wymagania
Zanim zaczniesz, upewnij się, że masz zainstalowane następujące narzędzia:

- Git: Do sklonowania repozytorium. 
- Docker: Silnik Docker, niezbędny do uruchamiania kontenerów.
- Docker Compose: Narzędzie do definiowania i uruchamiania wielokontenerowych aplikacji Dockerowych.
- OpenSSL: Będzie potrzebny do generowania certyfikatów SSL, jeśli install.sh nie może go użyć z kontenera. W środowisku GitHub Actions jest zwykle dostępny, ale lokalnie upewnij się, że masz go zainstalowanego (np. sudo apt install openssl na Ubuntu/Debian, lub zainstaluj z pakietów systemowych na innych OS-ach).
1. Zaktualizuj listę repozytoriów i zainstaluj git:
    ```bash
   sudo apt update &&
   sudo apt install git
    ```
2. Klonowanie repozytorium:
   
   ```bash
   git clone https://github.com/gacandrzej/apache-installer.git &&
   cd apache-installer
   ```
    

2. Nadanie uprawnień:
    ```bash
    chmod +x prepare_environment.sh
    ```
   
3. Uruchom skrypt:
   ```bash
   sudo ./prepare_environment.sh
   ```
   -   Skrypt będzie prosił o hasło sudo, ponieważ instaluje pakiety systemowe.
4. Co robi ten skrypt?
   - Sprawdza obecność: Git, OpenSSL, Docker i Docker Compose.
   - Instaluje brakujące: Jeśli któreś z narzędzi nie jest zainstalowane, skrypt spróbuje je zainstalować za pomocą apt. W przypadku Dockera używa oficjalnej metody instalacji, która zapewnia najnowsze i najbardziej stabilne wersje.
   - Zarządza uprawnieniami Dockera: Jeśli Docker jest instalowany, skrypt automatycznie dodaje bieżącego użytkownika do grupy docker. To pozwala na późniejsze uruchamianie komend docker bez sudo, choć Twój install.sh i tak używa sudo.
   - Ustawia prawa wykonywania: Upewnia się, że plik install.sh ma nadane prawa wykonywania.
   - Instrukcje po zakończeniu: Wyświetla komunikaty informujące użytkownika o konieczności ponownego zalogowania (jeśli dodano go do grupy docker) oraz instrukcje dotyczące dalszego uruchamiania projektu. 

5. Zbuduj obraz Dockera
    ```bash
    sudo docker build -t my-apache-ssl .
    ```
   
6. Nadanie uprawnień do wykonania:
```bash
chmod +x install.sh
``` 
   Ten skrypt zbuduje obraz Docker, skopiuje domyślne pliki konfiguracyjne Apache'a na hosta, wygeneruje samopodpisane certyfikaty SSL, skonfiguruje Apache'a do obsługi HTTPS i UserDir, a następnie uruchomi kontenery Docker Compose.
6. Co robi install.sh?
   - Buduje obraz Docker my-apache-ssl.
   - Kopiuje domyślne pliki konfiguracyjne Apache'a z nowo zbudowanego obrazu do katalogu apache_data/conf na Twoim hoście.
   - Generuje samopodpisane certyfikaty SSL i zapisuje je w apache_data/ssl.
   - Tworzy strukturę katalogów dla UserDir (np. apache_data/users/marek/public_html) i umieszcza w niej przykładowy plik index.html.
   - Modyfikuje skopiowane pliki konfiguracyjne Apache'a (httpd.conf, httpd-ssl.conf, httpd-userdir.conf) na hoście, aby włączyć obsługę SSL i UserDir oraz wskazać na wygenerowane certyfikaty.
   - Uruchamia kontenery Docker Compose, mapując odpowiednie porty i woluminy.

7. Uruchomienie skryptu:
   ```bash
   sudo ./install.sh
   ```
    
8. Dostęp do Serwera Apache
   Po pomyślnym uruchomieniu, serwer Apache będzie dostępny pod następującymi adresami:

      + HTTP (domyślna strona): http://localhost:80/
      + HTTPS (domyślna strona): https://localhost:443/
      
      + Przy pierwszym dostępie przez HTTPS, przeglądarka może wyświetlić ostrzeżenie o niezaufanym certyfikacie. To normalne, ponieważ używamy samopodpisanego certyfikatu. Możesz bezpiecznie zaakceptować ryzyko i kontynuować.
      + UserDir (dla użytkownika 'marek'):
        + HTTP: http://localhost/~marek/ (lub http://localhost/~marek/index.html jeśli masz konkretny plik)
        + HTTPS: https://localhost/~marek/ (lub https://localhost/~marek/index.html)
9. Struktura Projektu
   - . (katalog główny repozytorium):

   - Dockerfile: Definicja obrazu Docker dla Apache'a.
   
   - docker-compose.yml: Definicja usług Docker Compose (kontenera Apache).
   
   - install.sh: Główny skrypt do budowy, konfiguracji i uruchomienia projektu.
   
   - .github/workflows/main.yml: Konfiguracja GitHub Actions do automatycznego testowania.
   
   - apache_data/:
   
      - conf/: Katalog, do którego kopiowane są pliki konfiguracyjne Apache'a z kontenera (httpd.conf, extra/httpd-ssl.conf, extra/httpd-userdir.conf itd.) i są modyfikowane przez install.sh. Ten katalog jest montowany do kontenera.
   
      - htdocs/: Przykładowy katalog dla głównych plików strony internetowej. Jest montowany do kontenera.
   
      - logs/: Katalog na logi Apache'a. Jest montowany do kontenera.
   
      - ssl/: Katalog, w którym install.sh generuje certyfikaty server.key i server.crt. Jest montowany do kontenera. 
   
   - users/marek/public_html/: Przykładowy katalog dla funkcji UserDir użytkownika "marek". Jest montowany do kontenera jako /home/marek/public_html.
   
   - entrypoint.sh: Skrypt uruchamiany wewnątrz kontenera Apache'a przy jego starcie. Ustawia uprawnienia i uruchamia Apache'a na pierwszym planie. 
10. Jeśli użytkownik dostanie nowe zadanie dotyczące zawartości stron WWW (np. zmiana HTML, dodanie obrazów, plików CSS/JS), wystarczy, że zmodyfikuje odpowiednie pliki w katalogach na hoście:
    - (~/apache_data/htdocs lub 
    - ~/apache_data/public_html), 
    - a zmiany będą od razu widoczne w działającym kontenerze, bez potrzeby jego przebudowy czy restartu.


11. Jednorazowe kopiowanie konfiguracji: 
  * Skrypt install.sh sprawdza, czy pliki konfiguracyjne już istnieją w HOST_CONF_DIR. Jeśli nie, uruchamia tymczasowy kontener, kopiuje z niego świeżo zainstalowane pliki konfiguracyjne Apache'a i nanosi na nie początkowe poprawki (takie jak odkomentowanie modułów SSL/Userdir i ustawienie użytkownika/grupy). Dzięki temu użytkownik dostaje gotową, działającą konfigurację w swoim katalogu na hoście.
   
12. Łatwa edycja na hoście: Użytkownik może teraz swobodnie edytować pliki w ~/apache_data/conf za pomocą swoich ulubionych narzędzi.
   
13. Szybkie zmiany: Po edycji pliku konfiguracyjnego wystarczy jedno polecenie 
   ```bash
   sudo docker exec my-apache-container /usr/local/apache2/bin/apachectl restart 
   ```
    
   aby zmiany weszły w życie, bez długiej przebudowy obrazu.
   
14. Trwałe logi: Logi Apache'a (access_log, error_log, ssl_request_log) są również montowane do ~/apache_data/logs, co oznacza, że są trwałe i łatwo dostępne z hosta.

15. KONIEC.