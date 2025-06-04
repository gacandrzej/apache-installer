#!/bin/bash

APACHE_HOME="/usr/local/apache2"
APACHE_USER="apacheuser"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    exit 1
}

log_info "Uruchamianie entrypoint.sh dla kontenera Apache..."

# Test konfiguracji Apache'a
log_info "Testowanie konfiguracji Apache'a..."
${APACHE_HOME}/bin/apachectl configtest || log_error "Błąd konfiguracji Apache'a. Sprawdź logi."
log_info "Konfiguracja Apache'a poprawna (Syntax OK)."

# Sprawdzenie, czy moduł SSL został załadowany
log_info "Sprawdzanie, czy moduł SSL został załadowany..."
if ! ${APACHE_HOME}/bin/apachectl -M | grep -q "ssl_module (shared)"; then
    log_error "Moduł SSL (ssl_module) nie został załadowany poprawnie. Sprawdź logi błędów Apache'a."
fi
log_info "Moduł SSL (ssl_module) jest załadowany."

# Ustawienie uprawnień dla katalogów montowanych (na wypadek, gdyby host nie ustawił ich idealnie)
# Te komendy upewniają się, że użytkownik Apache'a ma prawa do odczytu i zapisu w tych katalogach.
log_info "Ustawianie uprawnień dla katalogów htdocs i public_html w kontenerze..."
chown -R ${APACHE_USER}:${APACHE_GROUP} ${APACHE_HOME}/htdocs || log_error "Nie udało się zmienić właściciela dla ${APACHE_HOME}/htdocs."
chmod -R 755 ${APACHE_HOME}/htdocs || log_error "Nie udało się zmienić uprawnień dla ${APACHE_HOME}/htdocs."

# Katalog domowy użytkownika Apache'a
mkdir -p /home/${APACHE_USER} # Upewnienie się, że istnieje, jeśli nie jest montowany
chown ${APACHE_USER}:${APACHE_GROUP} /home/${APACHE_USER}
chmod 751 /home/${APACHE_USER} # Uprawnienia dla katalogu domowego

# public_html w katalogu domowym użytkownika Apache'a
mkdir -p /home/${APACHE_USER}/public_html # Upewnienie się, że istnieje
chown -R ${APACHE_USER}:${APACHE_GROUP} /home/${APACHE_USER}/public_html
chmod -R 755 /home/${APACHE_USER}/public_html


log_info "Entrypoint wykonany. Uruchamiam Apache'a na pierwszym planie..."

# Uruchomienie Apache'a na pierwszym planie
exec ${APACHE_HOME}/bin/httpd -DFOREGROUND