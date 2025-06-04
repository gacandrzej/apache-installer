#!/bin/bash
set -ex

# Funkcje logowania
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    exit 1
}

# Definicje zmiennych
HOST_APACHE_DATA_BASE_DIR="$(pwd)/apache_data"
HOST_CONF_DIR="${HOST_APACHE_DATA_BASE_DIR}/conf"

# Upewnij się, że katalogi na hoście istnieją
mkdir -p "${HOST_CONF_DIR}" || log_error "Nie udało się utworzyć ${HOST_CONF_DIR}."
# Możesz dodać mkdir -p dla htdocs, logs, public_html_marek jeśli będą potrzebne w przyszłości
# mkdir -p "${HOST_APACHE_DATA_BASE_DIR}/htdocs"
# mkdir -p "${HOST_APACHE_DATA_BASE_DIR}/logs"
# mkdir -p "${HOST_APACHE_DATA_BASE_DIR}/public_html_marek"


log_info "Kopiowanie domyślnych plików konfiguracyjnych Apache'a z obrazu do '${HOST_CONF_DIR}'..."
# Usuń istniejące katalogi konfiguracyjne, aby mieć pewność, że zaczynamy od czystego stanu
rm -rf "${HOST_CONF_DIR}"
mkdir -p "${HOST_CONF_DIR}" || log_error "Nie udało się utworzyć ${HOST_CONF_DIR}."

# Stwórz tymczasowy kontener, aby skopiować z niego domyślne pliki konfiguracyjne
# Musisz użyć nazwy obrazu, która zostanie zbudowana przez Compose (my-apache-ssl)
TEMP_CONTAINER_ID=$(sudo docker create my-apache-ssl /bin/true)
sudo docker cp "${TEMP_CONTAINER_ID}:/usr/local/apache2/conf/." "${HOST_CONF_DIR}" || log_error "Nie udało się skopiować plików konfiguracyjnych z kontenera."
sudo docker rm "${TEMP_CONTAINER_ID}" > /dev/null

log_info "Modyfikowanie skopiowanych plików konfiguracyjnych na hoście..."

# --- Modyfikacje w httpd.conf (na hoście) ---
HTTPD_CONF_FILE_HOST="${HOST_CONF_DIR}/httpd.conf"

# Ustaw ServerName
sed -i 's/^#\(ServerName www\.example\.com:80\)/\1/' "${HTTPD_CONF_FILE_HOST}"
if ! grep -q "ServerName" "${HTTPD_CONF_FILE_HOST}"; then
    echo "ServerName localhost" >> "${HTTPD_CONF_FILE_HOST}"
else
    sed -i 's/^#*ServerName .*/ServerName localhost/' "${HTTPD_CONF_FILE_HOST}"
fi

# Odkomentuj moduł SSL
sed -i 's/^#\(LoadModule ssl_module\)/\1/' "${HTTPD_CONF_FILE_HOST}"

# Odkomentuj Listen 443
sed -i 's/^#\(Listen 443\)/\1/' "${HTTPD_CONF_FILE_HOST}"

# Odkomentuj include httpd-ssl.conf
sed -i 's/^#\(Include conf\/extra\/httpd-ssl.conf\)/\1/' "${HTTPD_CONF_FILE_HOST}"

# --- NOWE MODYFIKACJE DLA HTTPD-SSL.CONF ---
log_info 'Modyfikowanie httpd-ssl.conf na hoście, aby wskazywał na wygenerowane certyfikaty...'

# Upewnij się, że SSLEngine jest włączony (domyślnie może być, ale sprawdź)
# Jeśli nie ma "SSLEngine on", dodaj go pod VirtualHost, albo odkomentuj istniejący.
sed -i '/<VirtualHost _default_:443>/aSSLEngine on' "${HTTPD_SSL_CONF_FILE_HOST}"
# Jeśli już jest, ale zakomentowany, zmień na:
# sed -i 's/^#\(SSLEngine on\)/\1/' "${HTTPD_SSL_CONF_FILE_HOST}"

# Ustaw ścieżki do certyfikatów
# Upewnij się, że te linie są w sekcji <VirtualHost _default_:443>
sed -i 's|^SSLCertificateFile ".*"|SSLCertificateFile "/usr/local/apache2/conf/ssl/server.crt"|' "${HTTPD_SSL_CONF_FILE_HOST}"
sed -i 's|^SSLCertificateKeyFile ".*"|SSLCertificateKeyFile "/usr/local/apache2/conf/ssl/server.key"|' "${HTTPD_SSL_CONF_FILE_HOST}"

# Opcjonalnie: ustaw ServerName w httpd-ssl.conf, jeśli potrzebujesz
# Jeśli w httpd-ssl.conf masz ServerName www.example.com:443, zmień na localhost:443
sed -i 's/^ServerName .*$/ServerName localhost:443/' "${HTTPD_SSL_CONF_FILE_HOST}"

# Odkomentuj moduł zarządzania pamięcią podręczną dla SSL (mod_socache_shmcb)
sed -i 's/^#\(LoadModule socache_shmcb_module modules\/mod_socache_shmcb\.so\)/\1/' "${HTTPD_CONF_FILE_HOST}"

# WYŁĄCZANIE UserDir
sed -i 's/^Include conf\/extra\/httpd-userdir.conf/#Include conf\/extra\/httpd-userdir.conf/' "${HTTPD_CONF_FILE_HOST}"
sed -i 's/LoadModule userdir_module/#LoadModule userdir_module/' "${HTTPD_CONF_FILE_HOST}"

# Upewnij się, że Apache loguje do stdout/stderr
sed -i 's/^ErrorLog .*$/ErrorLog "\/dev\/stderr"/' "${HTTPD_CONF_FILE_HOST}"
sed -i 's/^CustomLog .*$/CustomLog "\/dev\/stdout" combined/' "${HTTPD_CONF_FILE_HOST}"

# Zmień ścieżkę do pliku PID i LockFile na /tmp
sed -i 's|^PidFile "logs/httpd.pid"|PidFile "/tmp/httpd.pid"|' "${HTTPD_CONF_FILE_HOST}"
sed -i 's|^LockFile "logs/accept.lock"|LockFile "/tmp/accept.lock"|' "${HTTPD_CONF_FILE_HOST}"

log_info "Domyślne pliki konfiguracyjne zostały skopiowane i zmodyfikowane na hoście."

# --- Uruchamianie za pomocą Docker Compose ---
log_info "Uruchamianie usług Docker Compose..."
# 'docker compose up -d' zbuduje obraz (jeśli go nie ma lub zmienił się Dockerfile)
# i uruchomi kontener w tle.
sudo docker compose up -d --build --force-recreate || log_error "Nie udało się uruchomić usług Docker Compose."

# Możesz dodać krótki sleep, aby dać kontenerowi czas na uruchomienie
sleep 5

log_info "Weryfikacja statusu kontenerów Docker Compose:"
sudo docker compose ps

# Wyświetl logi z usługi Apache (to samo co docker logs)
log_info "Wyświetlanie logów z usługi Apache (docker compose logs apache):"
sudo docker compose logs apache

# Przykładowy test curl (jeśli Apache działa, ale HTTP jest niedostępne)
# sudo docker compose exec apache curl -s -o /dev/null -w "HTTP Code: %{http_code}\n" http://localhost:80/ || true

log_info "Skrypt install.sh zakończył działanie."