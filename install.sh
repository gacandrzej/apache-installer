#!/bin/bash

IMAGE_NAME="my-apache-ssl"
CONTAINER_NAME="my-apache-container"
COMMON_NAME="zsmeie"
APACHE_HOME_CONTAINER="/usr/local/apache2" # Ścieżka Apache w kontenerze
APACHE_USER_CONTAINER="www-data" # Użytkownik Apache'a w kontenerze

# Katalogi na hoście, które będą montowane
HOST_APACHE_DATA_DIR="${HOME}/apache_data"
HOST_HTDOCS_DIR="${HOST_APACHE_DATA_DIR}/htdocs"
HOST_PUBLIC_HTML_DIR="${HOST_APACHE_DATA_DIR}/public_html"
HOST_LOGS_DIR="${HOST_APACHE_DATA_DIR}/logs"
HOST_CONF_DIR="${HOST_APACHE_DATA_DIR}/conf" # Nowy katalog dla konfiguracji Apache'a na hoście

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    exit 1
}

log_info "Rozpoczynam instalację i uruchamianie Apache'a w Dockerze."

# Sprawdzenie, czy Docker jest zainstalowany i uruchomiony
if ! command -v docker &> /dev/null; then
    log_error "Docker nie jest zainstalowany. Proszę zainstalować Docker Engine: https://docs.docker.com/engine/install/"
fi
if ! sudo docker info &> /dev/null; then
    log_error "Docker Engine nie jest uruchomiony lub użytkownik nie ma uprawnień do Dockera. Upewnij się, że usługa Docker jest aktywna i że jesteś w grupie 'docker' (sudo usermod -aG docker $USER && newgrp docker)."
fi

# Zatrzymywanie i usuwanie starego kontenera (jeśli istnieje)
log_info "Sprawdzanie, czy kontener '${CONTAINER_NAME}' już istnieje..."
if sudo docker ps -a --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    log_info "Kontener '${CONTAINER_NAME}' już istnieje. Zatrzymuję i usuwam go..."
    sudo docker stop "${CONTAINER_NAME}" || log_error "Nie udało się zatrzymać kontenera '${CONTAINER_NAME}'."
    sudo docker rm "${CONTAINER_NAME}" || log_error "Nie udało się usunąć kontenera '${CONTAINER_NAME}'."
fi

# Usuwanie starego obrazu (jeśli istnieje)
log_info "Sprawdzanie, czy obraz '${IMAGE_NAME}' już istnieje..."
if sudo docker images --format '{{.Repository}}' | grep -q "${IMAGE_NAME}"; then
    log_info "Obraz '${IMAGE_NAME}' już istnieje. Usuwam go, aby zbudować najnowszą wersję..."
    sudo docker rmi "${IMAGE_NAME}" || log_error "Nie udało się usunąć obrazu '${IMAGE_NAME}'. Upewnij się, że nie jest używany."
fi

# --- Tworzenie katalogów danych na hoście i wstępne pliki ---
log_info "Tworzenie katalogów danych Apache na hoście w: ${HOST_APACHE_DATA_DIR}"
mkdir -p "${HOST_HTDOCS_DIR}" || log_error "Nie udało się utworzyć ${HOST_HTDOCS_DIR}."
mkdir -p "${HOST_PUBLIC_HTML_DIR}" || log_error "Nie udało się utworzyć ${HOST_PUBLIC_HTML_DIR}."
mkdir -p "${HOST_LOGS_DIR}" || log_error "Nie udało się utworzyć ${HOST_LOGS_DIR}."
mkdir -p "${HOST_CONF_DIR}/extra" || log_error "Nie udało się utworzyć ${HOST_CONF_DIR}/extra." # Tworzymy też podkatalog extra
# --- Tworzenie katalogu SSL i generowanie certyfikatów na hoście ---
HOST_SSL_DIR="${HOST_CONF_DIR}/ssl" # Definiujemy katalog SSL na hoście

log_info "Sprawdzanie certyfikatów SSL na hoście w: ${HOST_SSL_DIR}"
mkdir -p "${HOST_SSL_DIR}" || log_error "Nie udało się utworzyć ${HOST_SSL_DIR}."

if [ ! -f "${HOST_SSL_DIR}/server.key" ] || [ ! -f "${HOST_SSL_DIR}/server.crt" ]; then
    log_info "Generowanie samo-podpisanego certyfikatu SSL na hoście..."
    openssl genrsa -out "${HOST_SSL_DIR}/server.key" 2048 || log_error "Nie udało się wygenerować server.key."
    chmod 600 "${HOST_SSL_DIR}/server.key" || log_error "Nie udało się ustawić uprawnień dla server.key."
    openssl req -x509 -new -nodes -key "${HOST_SSL_DIR}/server.key" \
        -sha256 -days 365 -out "${HOST_SSL_DIR}/server.crt" \
        -subj "/C=PL/ST=Kujawsko-Pomorskie/L=Toruń/O=ZSMEiE/OU=IT/CN=${COMMON_NAME}/emailAddress=admin@zsmeie.pl" || log_error "Nie udało się wygenerować server.crt."
    log_info "Certyfikaty SSL zostały wygenerowane na hoście."
else
    log_info "Certyfikaty SSL już istnieją na hoście. Pomijam generowanie."
fi
# --- Koniec tworzenia certyfikatów SSL na hoście ---

log_info "Ustawianie początkowych uprawnień dla katalogów danych na hoście..."
# Uprawnienia dla ogólnych katalogów danych (dla użytkownika hosta)
sudo chmod 755 "${HOST_APACHE_DATA_DIR}" "${HOST_HTDOCS_DIR}" "${HOST_PUBLIC_HTML_DIR}" "${HOST_LOGS_DIR}" "${HOST_CONF_DIR}" "${HOST_CONF_DIR}/extra" || log_error "Nie udało się ustawić uprawnień dla katalogów danych na hoście."

# Ustawienie właściciela katalogów dla Apache'a - ważne, aby użytkownik Apache'a w kontenerze mógł zapisywać logi
# I aby mieć prawa do public_html
# Znajdź UID/GID użytkownika APACHE_USER w kontenerze
# Należy pamiętać, że `docker run` tworzy nowego użytkownika `apacheuser` o ID, które może być różne od UID/GID na hoście.
# Najbezpieczniej jest, aby użytkownik, pod którym działa proces w kontenerze, miał odpowiednie uprawnienia do zamontowanego katalogu.
# Domyślnie, jeśli proces w kontenerze działa jako `root`, to ma pełny dostęp.
# Ale ponieważ stworzyliśmy `apacheuser`, musimy upewnić się, że to działa.
# Najprościej:
# chown -R 33:33 /var/www/html (dla Debiana/Ubuntu domyślny www-data)
# ale tutaj nie możemy wiedzieć, jakie ID ma apacheuser w kontenerze.
# Rozwiązaniem jest użycie nazwy użytkownika w chown po zamontowaniu, tak jak w entrypoint.sh.
# Na hoście uprawnienia mogą pozostać dla bieżącego użytkownika (czyli tego, który uruchamia skrypt)
# lub nadać wszystkim grupie dostęp do zapisu (np. 775 i dodać użytkownika apache do grupy).
# Na potrzeby tego skryptu edukacyjnego, zakładamy, że `entrypoint.sh` poradzi sobie z uprawnieniami w kontenerze.

log_info "Tworzenie przykładowych plików index.html w katalogach danych na hoście..."
echo "<html><body><h1>Witaj na glownej stronie (htdocs) hostowanej przez Docker!</h1></body></html>" > "${HOST_HTDOCS_DIR}/index.html"
echo "<html><body><h1>Witaj na stronie uzytkownika (public_html) hostowanej przez Docker!</h1></body></html>" > "${HOST_PUBLIC_HTML_DIR}/index.html"

# --- Koniec tworzenia katalogów danych ---

# Zbudowanie obrazu Dockera
log_info "Rozpoczynam budowanie obrazu Dockera '${IMAGE_NAME}'..."
SCRIPT_DIR=$(dirname "$0")
cd "${SCRIPT_DIR}" || log_error "Nie można przejść do katalogu skryptu."

sudo docker build -t "${IMAGE_NAME}" . || log_error "Nie udało się zbudować obrazu Dockera."
log_info "Obraz Dockera '${IMAGE_NAME}' został zbudowany pomyślnie."


# --- Kopiowanie domyślnej konfiguracji Apache'a z obrazu do hosta (TYLKO RAZ) ---
if [ ! -f "${HOST_CONF_DIR}/httpd.conf" ]; then
    log_info "Kopiowanie domyślnych plików konfiguracyjnych Apache'a z obrazu do '${HOST_CONF_DIR}'..."
    # Uruchom tymczasowy kontener, skopiuj pliki, a następnie usuń kontener
    TMP_CONTAINER_NAME="tmp-apache-config-copier"
    sudo docker run --name "${TMP_CONTAINER_NAME}" -d "${IMAGE_NAME}" tail -f /dev/null || log_error "Nie udało się uruchomić tymczasowego kontenera do kopiowania konfiguracji."
    log_info "Wykonywanie kopii plików konfiguracyjnych..."
    sudo docker cp "${TMP_CONTAINER_NAME}:${APACHE_HOME_CONTAINER}/conf/httpd.conf" "${HOST_CONF_DIR}/httpd.conf" || log_error "Nie udało się skopiować httpd.conf."
    sudo docker cp "${TMP_CONTAINER_NAME}:${APACHE_HOME_CONTAINER}/conf/magic" "${HOST_CONF_DIR}/magic" || log_error "Nie udało się skopiować magic."
    sudo docker cp "${TMP_CONTAINER_NAME}:${APACHE_HOME_CONTAINER}/conf/mime.types" "${HOST_CONF_DIR}/mime.types" || log_error "Nie udało się skopiować mime.types."
    # Kopiowanie całego katalogu extra
    sudo docker cp "${TMP_CONTAINER_NAME}:${APACHE_HOME_CONTAINER}/conf/extra/." "${HOST_CONF_DIR}/extra/" || log_error "Nie udało się skopiować katalogu extra."

    # Modyfikacje w skopiowanych plikach konfiguracyjnych (jak wcześniej w Dockerfile)
    log_info "Modyfikowanie skopiowanych plików konfiguracyjnych na hoście..."
    # Odkomentuj LoadModule ssl_module i Include conf/extra/httpd-ssl.conf w httpd.conf
    sed -i 's/^#LoadModule ssl_module modules\/mod_ssl.so/LoadModule ssl_module modules\/mod_ssl.so/' "${HOST_CONF_DIR}/httpd.conf"
    sed -i 's/^#Include conf\/extra\/httpd-ssl.conf/Include conf\/extra\/httpd-ssl.conf/' "${HOST_CONF_DIR}/httpd.conf"
    # Odkomentuj LoadModule userdir_module i Include conf/extra/httpd-userdir.conf w httpd.conf
    sed -i 's/^#LoadModule userdir_module modules\/mod_userdir.so/LoadModule userdir_module modules\/mod_userdir.so/' "${HOST_CONF_DIR}/httpd.conf"
    sed -i 's/^#Include conf\/extra\/httpd-userdir.conf/Include conf\/extra\/httpd-userdir.conf/' "${HOST_CONF_DIR}/httpd.conf"
    # Odkomentuj LoadModule socache_shmcb_module w httpd.conf
    sed -i 's/^#LoadModule socache_shmcb_module modules\/mod_socache_shmcb.so/LoadModule socache_shmcb_module modules\/mod_socache_shmcb.so/' "${HOST_CONF_DIR}/httpd.conf"
    # Upewnij się, że ta linia znajduje się w httpd.conf; jeśli nie, dodaj ją
    if ! grep -q "LoadModule socache_shmcb_module" "${HOST_CONF_DIR}/httpd.conf"; then
        echo "LoadModule socache_shmcb_module modules/mod_socache_shmcb.so" >> "${HOST_CONF_DIR}/httpd.conf"
    fi

    # Zmieniamy użytkownika i grupę w httpd.conf
    sed -i "s/^User daemon/User ${APACHE_USER_CONTAINER}/" "${HOST_CONF_DIR}/httpd.conf"
    sed -i "s/^Group daemon/Group ${APACHE_USER_CONTAINER}/" "${HOST_CONF_DIR}/httpd.conf"

    # Edytuj plik httpd-ssl.conf na hoście
    SSL_CONF_FILE_HOST="${HOST_CONF_DIR}/extra/httpd-ssl.conf"
    sed -i "s|DocumentRoot \".*\"|DocumentRoot \"${APACHE_HOME_CONTAINER}/htdocs\"|" "${SSL_CONF_FILE_HOST}"
    sed -i "s|ServerName www.example.com:443|ServerName ${COMMON_NAME}:443|" "${SSL_CONF_FILE_HOST}"
    sed -i "s|ServerAdmin you@example.com|ServerAdmin admin@zsmeie.pl|" "${SSL_CONF_FILE_HOST}"
    # SSLCertificateFile i SSLCertificateKeyFile nadal wskazują na pliki w kontenerze, bo certyfikat jest generowany w obrazie
    sed -i "s|SSLCertificateFile \".*\"|SSLCertificateFile \"${APACHE_HOME_CONTAINER}/conf/ssl/server.crt\"|" "${SSL_CONF_FILE_HOST}"
    sed -i "s|SSLCertificateKeyFile \".*\"|SSLCertificateKeyFile \"${APACHE_HOME_CONTAINER}/conf/ssl/server.key\"|" "${SSL_CONF_FILE_HOST}"

    # Edytuj plik httpd-userdir.conf na hoście
    USERDIR_CONF_FILE_HOST="${HOST_CONF_DIR}/extra/httpd-userdir.conf"
    sed -i 's/^UserDir public_html/UserDir public_html/' "${USERDIR_CONF_FILE_HOST}"
    sed -i '/<Directory "\/home\/user\/public_html">/,/<\/Directory>/s|Require all denied|Require all granted|' "${USERDIR_CONF_FILE_HOST}"
    sed -i '/<Directory "\/home\/user\/public_html">/,/<\/Directory>/s|AllowOverride None|AllowOverride All|' "${USERDIR_CONF_FILE_HOST}"

    log_info "Domyślne pliki konfiguracyjne zostały skopiowane i zmodyfikowane na hoście."
    sudo docker stop "${TMP_CONTAINER_NAME}" &> /dev/null # Zatrzymaj i usuń tymczasowy kontener
    sudo docker rm "${TMP_CONTAINER_NAME}" &> /dev/null
else
    log_info "Katalog konfiguracyjny '${HOST_CONF_DIR}' już istnieje z plikami konfiguracyjnymi. Pomijam kopiowanie."
fi
# --- Koniec kopiowania domyślnej konfiguracji ---


# Uruchomienie kontenera z woluminami
log_info "Uruchamiam kontener '${CONTAINER_NAME}' na portach 80 i 443 z zamontowanymi woluminami..."
sudo docker run -d \
    -p 80:80 \
    -p 443:443 \
    -v "${HOST_HTDOCS_DIR}":"${APACHE_HOME_CONTAINER}/htdocs" \
    -v "${HOST_PUBLIC_HTML_DIR}":"/home/${APACHE_USER_CONTAINER}/public_html" \
    -v "${HOST_LOGS_DIR}":"${APACHE_HOME_CONTAINER}/logs" \
    -v "${HOST_CONF_DIR}":"${APACHE_HOME_CONTAINER}/conf" \
    --name "${CONTAINER_NAME}" \
    "${IMAGE_NAME}" || log_error "Nie udało się uruchomić kontenera Dockera."
log_info "Kontener '${CONTAINER_NAME}' uruchomiony w tle z woluminami."

# Wyświetlanie logów kontenera w czasie rzeczywistym
log_info "Wyświetlam logi kontenera (Ctrl+C, aby zakończyć śledzenie logów i pozostawić kontener uruchomiony):"
sudo docker logs -f "${CONTAINER_NAME}"

log_info "Instalacja i uruchomienie zakończone."
log_info "Możesz teraz sprawdzić działanie strony głównej: http://localhost oraz https://localhost"
log_info "Strona użytkownika będzie dostępna pod adresem: https://localhost/~apacheuser/"
log_info "Pamiętaj, że certyfikat jest samo-podpisany, więc przeglądarka wyświetli ostrzeżenie."
log_info ""
log_info "--- Jak zmieniać konfigurację Apache'a ---"
log_info "Pliki konfiguracyjne Apache'a znajdują się na hoście w katalogu:"
log_info "  - ${HOST_CONF_DIR}"
log_info "Aby zmienić konfigurację (np. dodać Virtual Host, zmienić port):"
log_info "1. Edytuj odpowiedni plik konfiguracyjny (np. ${HOST_CONF_DIR}/httpd.conf lub ${HOST_CONF_DIR}/extra/httpd-vhosts.conf)."
log_info "2. Zrestartuj Apache'a w kontenerze poleceniem:"
log_info "   sudo docker exec ${CONTAINER_NAME} ${APACHE_HOME_CONTAINER}/bin/apachectl restart"
log_info ""
log_info "Wszelkie zmiany w plikach na hoście w katalogach:"
log_info "  - ${HOST_HTDOCS_DIR} (dla strony głównej)"
log_info "  - ${HOST_PUBLIC_HTML_DIR} (dla stron użytkownika)"
log_info "Będą natychmiast widoczne w kontenerze, bez potrzeby restartu Apache'a."
log_info "Logi Apache'a znajdziesz na hoście w: ${HOST_LOGS_DIR}"
log_info "Jeśli chcesz zatrzymać kontener: 'sudo docker stop ${CONTAINER_NAME}'"
log_info "Jeśli chcesz usunąć kontener: 'sudo docker rm ${CONTAINER_NAME}'"