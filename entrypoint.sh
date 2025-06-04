#!/bin/bash
set -ex
APACHE_HOME="/usr/local/apache2"
APACHE_USER="www-data"
APACHE_GROUP="www-data"
USER_MAREK="marek"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    exit 1
}

log_info "Uruchamianie entrypoint.sh dla kontenera Apache..."

# Ustawianie uprawnień dla katalogów, które są zamontowane z hosta
# Upewnij się, że użytkownik Apache'a ma prawa do odczytu/zapisu.
# Woluminy mogą nadpisać uprawnienia kontenera, więc ustawiamy je na bieżąco.

log_info "Ustawianie uprawnień dla zamontowanych woluminów danych..."

# httpd.conf i inne pliki konfiguracyjne:
# Muszą być czytelne dla użytkownika Apache'a.
# Zwykle te pliki są montowane jako read-only, ale dla pewności ustawiamy.
chown -R root:${APACHE_GROUP} ${APACHE_HOME}/conf || log_error "Nie udało się zmienić właściciela dla ${APACHE_HOME}/conf."
chmod -R 755 ${APACHE_HOME}/conf || log_error "Nie udało się zmienić uprawnień dla ${APACHE_HOME}/conf."
# SSL klucze powinny być tylko dla roota
chown root:root ${APACHE_HOME}/conf/ssl/server.key
chmod 600 ${APACHE_HOME}/conf/ssl/server.key

# htdocs: katalog główny stron WWW
chown -R ${APACHE_USER}:${APACHE_GROUP} ${APACHE_HOME}/htdocs || log_error "Nie udało się zmienić właściciela dla ${APACHE_HOME}/htdocs."
chmod -R 755 ${APACHE_HOME}/htdocs || log_error "Nie udało się zmienić uprawnień dla ${APACHE_HOME}/htdocs."

chmod 751 /home/${APACHE_USER} # R-X dla innych (Apache potrzebuje wejścia)

# Uprawnienia dla katalogu domowego Marka (będzie zamontowany)
# Ważne: Jeśli /home/marek nie będzie montowany, ale tylko /home/marek/public_html,
# to entrypoint powinien tylko zajmować się /home/marek/public_html.
# Jeśli montujesz całe /home/marek, to dostosuj:
if [ -d "/home/${USER_MAREK}/public_html" ]; then
    chown -R ${USER_MAREK}:${APACHE_USER} /home/${USER_MAREK}/public_html
    chmod -R 755 /home/${USER_MAREK}/public_html
else
    log_info "Katalog public_html dla ${USER_MAREK} nie został znaleziony (może nie jest zamontowany). Pomijam ustawianie uprawnień."
fi
# logs: katalog logów Apache'a
chown -R ${APACHE_USER}:${APACHE_GROUP} ${APACHE_HOME}/logs || log_error "Nie udało się zmienić właściciela dla ${APACHE_HOME}/logs."
chmod -R 755 ${APACHE_HOME}/logs || log_error "Nie udało się zmienić uprawnień dla ${APACHE_HOME}/logs."


log_info "Uprawnienia woluminów danych ustawione pomyślnie."

# Test konfiguracji Apache'a
log_info "Testowanie konfiguracji Apache'a..."

# Przechwyć wyjście apachectl configtest i sprawdź kod wyjścia
APACHECTL_OUTPUT=$(/usr/local/apache2/bin/apachectl configtest 2>&1)
APACHECTL_EXIT_CODE=$? # Przechwyć kod wyjścia ostatniego polecenia

if [ ${APACHECTL_EXIT_CODE} -ne 0 ]; then
    echo "ERROR: Apache configtest failed with exit code ${APACHECTL_EXIT_CODE}."
    echo "--- Apache configtest output ---"
    echo "${APACHECTL_OUTPUT}" # Wypisz całe przechwycone wyjście
    echo "-------------------------------"
    exit 1 # Natychmiast zakończ skrypt z błędem
else
    # Ta linia zostanie wykonana TYLKO JEŚLI configtest zakończy się sukcesem (exit code 0)
    log_info "Konfiguracja Apache'a poprawna (Syntax OK)."
fi

# Upewnij się, że ServerName jest ustawiony w httpd.conf, aby uniknąć ostrzeżeń
APACHE_CONF_FILE="${APACHE_HOME}/conf/httpd.conf"
if ! grep -q "ServerName" "${APACHE_CONF_FILE}"; then
    echo "ServerName localhost" >> "${APACHE_CONF_FILE}"
else
    sed -i 's/^#*ServerName .*/ServerName localhost/' "${APACHE_CONF_FILE}"
fi

# Sprawdzenie, czy moduł SSL został załadowany
log_info "Sprawdzanie, czy moduł SSL został załadowany..."
if ! ${APACHE_HOME}/bin/apachectl -M | grep -q "ssl_module (shared)"; then
    log_error "Moduł SSL (ssl_module) nie został załadowany poprawnie. Sprawdź logi błędów Apache'a."
fi
log_info "Moduł SSL (ssl_module) jest załadowany."

log_info "Entrypoint wykonany. Uruchamiam Apache'a na pierwszym planie..."

# Uruchomienie Apache'a na pierwszym planie
exec ${APACHE_HOME}/bin/httpd -DFOREGROUND "$@" || { echo "Apache failed to start. Check command/config." && exit 1; }