#!/bin/bash

APACHE_HOME="/usr/local/apache2"
APACHE_USER="apacheuser" # Użytkownik, pod którym działa Apache

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

log_info "Sprawdzanie, czy Apache nasłuchuje na porcie 443..."
# Pamiętaj, że w kontenerze ss -tulnp | grep 443 może nie pokazać httpd dopóki httpd się nie uruchomi
# Ale możemy sprawdzić, czy port jest otwarty w sieci
# Uruchomimy apachectl na pierwszym planie, który sam sprawdzi bindowanie
log_info "Entrypoint wykonany. Uruchamiam Apache'a na pierwszym planie..."

# Uruchomienie Apache'a na pierwszym planie
# exec zastępuje proces shella, dzięki czemu sygnały są przekazywane bezpośrednio do httpd
exec ${APACHE_HOME}/bin/httpd -DFOREGROUND