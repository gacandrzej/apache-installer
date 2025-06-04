# apache-installer
1. Klonowanie repozytorium:


    git clone https://github.com/TwojaNazwaUzytkownika/apache-installer.git

    cd apache-installer

2. Nadanie uprawnień do wykonania:

    chmod +x install.sh

3. Uruchomienie skryptu:

    ./install.sh


4.  Jeśli użytkownik dostanie nowe zadanie dotyczące zawartości stron WWW (np. zmiana HTML, dodanie obrazów, plików CSS/JS), wystarczy, że zmodyfikuje odpowiednie pliki w katalogach na hoście (~/apache_data/htdocs lub ~/apache_data/public_html), a zmiany będą od razu widoczne w działającym kontenerze, bez potrzeby jego przebudowy czy restartu