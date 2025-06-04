#!/bin/bash
set -ex

# ... (pozostała część Twojego skryptu install.sh)

# Definicje zmiennych (upewnij się, że są zgodne z Twoimi)
HOST_APACHE_DATA_DIR="/root/apache_data"
HOST_CONF_DIR="${HOST_APACHE_DATA_DIR}/conf"
HOST_HTDOCS_DIR="${HOST_APACHE_DATA_DIR}/htdocs"
HOST_LOGS_DIR="${HOST_APACHE_DATA_DIR}/logs"
HOST_PUBLIC_HTML_MAREK_DIR="${HOST_APACHE_DATA_DIR}/public_html_marek"

CONTAINER_NAME="my-apache-container"
IMAGE_NAME="my-apache-ssl" # Zostawiamy nazwę obrazu, bo może już zawierać zależności SSL
APACHE_USER_CONTAINER="www-data"
USER_MAREK="marek"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    exit 1
}

# ... (pomijam sekcję budowania obrazu, zakładamy, że działa)

log_info "Kopiowanie domyślnych plików konfiguracyjnych Apache'a z obrazu do '${HOST_CONF_DIR}'..."
# Usuń istniejące katalogi konfiguracyjne, aby mieć pewność, że zaczynamy od czystego stanu
rm -rf "${HOST_CONF_DIR}"
mkdir -p "${HOST_CONF_DIR}" || log_error "Nie udało się utworzyć ${HOST_CONF_DIR}."

# Skopiuj domyślne pliki konfiguracyjne Apache'a z kontenera
# Używamy tymczasowego kontenera, aby to zrobić
TEMP_CONTAINER_ID=$(sudo docker create "${IMAGE_NAME}" /bin/true)
sudo docker cp "${TEMP_CONTAINER_ID}:/usr/local/apache2/conf/." "${HOST_CONF_DIR}" || log_error "Nie udało się skopiować plików konfiguracyjnych z kontenera."
sudo docker rm "${TEMP_CONTAINER_ID}" > /dev/null

log_info "Wykonywanie kopii plików konfiguracyjnych..."

log_info "Modyfikowanie skopiowanych plików konfiguracyjnych na hoście..."

# --- Modyfikacje w httpd.conf (na hoście) ---
HTTPD_CONF_FILE_HOST="${HOST_CONF_DIR}/httpd.conf"

# Ustaw ServerName, aby uniknąć ostrzeżeń przy starcie
sed -i 's/^#\(ServerName www\.example\.com:80\)/\1/' "${HTTPD_CONF_FILE_HOST}"
if ! grep -q "ServerName" "${HTTPD_CONF_FILE_HOST}"; then
    echo "ServerName localhost" >> "${HTTPD_CONF_FILE_HOST}"
else
    sed -i 's/^#*ServerName .*/ServerName localhost/' "${HTTPD_CONF_FILE_HOST}"
fi

# WYŁĄCZANIE SSL (zakomentowanie linii Include httpd-ssl.conf)
# Zmieniamy 'Include' na '#Include' dla httpd-ssl.conf
sed -i 's/^Include conf\/extra\/httpd-ssl.conf/#Include conf\/extra\/httpd-ssl.conf/' "${HTTPD_CONF_FILE_HOST}"
# Zakomentuj linie LoadModule ssl_module
sed -i 's/LoadModule ssl_module/#LoadModule ssl_module/' "${HTTPD_CONF_FILE_HOST}"
# Zakomentuj linie Listen 443
sed -i 's/Listen 443/#Listen 443/' "${HTTPD_CONF_FILE_HOST}"

# WYŁĄCZANIE UserDir (zakomentowanie linii Include httpd-userdir.conf)
sed -i 's/^Include conf\/extra\/httpd-userdir.conf/#Include conf\/extra\/httpd-userdir.conf/' "${HTTPD_CONF_FILE_HOST}"
# Zakomentuj linie LoadModule userdir_module
sed -i 's/LoadModule userdir_module/#LoadModule userdir_module/' "${HTTPD_CONF_FILE_HOST}"


# --- Modyfikacje w httpd-ssl.conf (jeśli istnieje, dla pewności, choć już nie będzie include'owany) ---
# Należy pamiętać, że jeśli httpd-ssl.conf nie jest dołączany, te modyfikacje są zbędne,
# ale możemy je zastosować dla porządku.
# Możesz nawet usunąć ten plik, ale na razie go po prostu ignorujemy.

# --- Modyfikacje w httpd-userdir.conf (jeśli istnieje, dla pewności, choć już nie będzie include'owany) ---
# Podobnie jak wyżej, te modyfikacje staną się zbędne po zakomentowaniu Include w httpd.conf.

log_info "Domyślne pliki konfiguracyjne zostały skopiowane i zmodyfikowane na hoście."

# Upewnij się, że Apache loguje do stdout/stderr
# (Powinien to już robić domyślnie w oficjalnych obrazach, ale dla pewności)
# Możesz dodać:
sed -i 's/^ErrorLog .*$/ErrorLog "\/dev\/stderr"/' "${HTTPD_CONF_FILE_HOST}"
sed -i 's/^CustomLog .*$/CustomLog "\/dev\/stdout" combined/' "${HTTPD_CONF_FILE_HOST}"

# Zmień ścieżkę do pliku PID, na miejsce w /tmp lub /var/run, które jest woluminem tymczasowym kontenera
# i nie jest montowane z hosta. To eliminuje problemy z uprawnieniami na hoście.
sed -i 's|^PidFile "logs/httpd.pid"|PidFile "/tmp/httpd.pid"|' "${HTTPD_CONF_FILE_HOST}"

# Jeśli masz dyrektywę LockFile (niektóre starsze wersje Apache'a), zmień ją też
sed -i 's|^LockFile "logs/accept.lock"|LockFile "/tmp/accept.lock"|' "${HTTPD_CONF_FILE_HOST}"

# Uruchamiam kontener 'my-apache-container' na portach 80 (tylko HTTP) z zamontowanymi woluminami...
# Ważne: Usuń mapowanie portu 443!
sudo docker run -d --name "${CONTAINER_NAME}" \
    -p 80:80 \
    -v "${HOST_CONF_DIR}":"/usr/local/apache2/conf:ro" \
   # -v "${HOST_HTDOCS_DIR}":"/usr/local/apache2/htdocs"
   # -v "${HOST_LOGS_DIR}":"/usr/local/apache2/logs"
   # -v "${HOST_PUBLIC_HTML_MAREK_DIR}":"/home/${USER_MAREK}/public_html"
    "${IMAGE_NAME}" || log_error "Nie udało się uruchomić kontenera '${CONTAINER_NAME}'."


# ... (reszta skryptu z logami i sprawdzaniem kontenera)
# Upewnij się, że masz już tę poprawioną sekcję z logami z poprzedniej odpowiedzi:
log_info "Kontener '${CONTAINER_NAME}' uruchomiony w tle z woluminami."

sleep 5 # Daj Apache'owi chwilę na start
if sudo docker ps -q | grep -q "${CONTAINER_NAME}"; then
    log_info "Kontener '${CONTAINER_NAME}' działa pomyślnie. Wyświetlam ostatnie 100 linii logów:"
    sudo docker logs --tail 100 "${CONTAINER_NAME}"
else
    log_error "Kontener '${CONTAINER_NAME}' nie działa po uruchomieniu. Pokażę jego logi błędów:"
    sudo docker logs --details "${CONTAINER_NAME}"
    exit 1
fi

log_info "Działania związane z uruchomieniem kontenera zakończone."

# ... (ewentualne testy curl)