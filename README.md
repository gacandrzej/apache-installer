# apache-installer
1. Klonowanie repozytorium:


    git clone https://github.com/TwojaNazwaUzytkownika/apache-installer.git

    cd apache-installer

2. Nadanie uprawnień do wykonania:

    chmod +x install.sh

3. Uruchomienie skryptu:

    ./install.sh


4.  Jeśli użytkownik dostanie nowe zadanie dotyczące zawartości stron WWW (np. zmiana HTML, dodanie obrazów, plików CSS/JS), wystarczy, że zmodyfikuje odpowiednie pliki w katalogach na hoście (~/apache_data/htdocs lub ~/apache_data/public_html), 
a zmiany będą od razu widoczne w działającym kontenerze, bez potrzeby jego przebudowy czy restartu.


5. Jednorazowe kopiowanie konfiguracji: Skrypt install.sh sprawdza, czy pliki konfiguracyjne już istnieją w HOST_CONF_DIR. Jeśli nie, uruchamia tymczasowy kontener, kopiuje z niego świeżo zainstalowane pliki konfiguracyjne Apache'a i nanosi na nie początkowe poprawki (takie jak odkomentowanie modułów SSL/Userdir i ustawienie użytkownika/grupy). Dzięki temu użytkownik dostaje gotową, działającą konfigurację w swoim katalogu na hoście.
   
6. Łatwa edycja na hoście: Użytkownik może teraz swobodnie edytować pliki w ~/apache_data/conf za pomocą swoich ulubionych narzędzi.
   
7. Szybkie zmiany: Po edycji pliku konfiguracyjnego wystarczy jedno polecenie 

    sudo docker exec my-apache-container /usr/local/apache2/bin/apachectl restart, 

   aby zmiany weszły w życie, bez długiej przebudowy obrazu.
   
7. Trwałe logi: Logi Apache'a (access_log, error_log, ssl_request_log) są również montowane do ~/apache_data/logs, co oznacza, że są trwałe i łatwo dostępne z hosta.