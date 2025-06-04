#!/bin/bash

IMAGE_NAME="my-apache-ssl"
CONTAINER_NAME="my-apache-container"
COMMON_NAME="zsmeie"
APACHE_HOME_CONTAINER="/usr/local/apache2" # Ścieżka Apache w kontenerze

# Katalogi na hoście, które będą montowane
HOST_APACHE_DATA_DIR="${HOME}/apache_data"
HOST_HTDOCS_DIR="${HOST_APACHE_DATA_DIR}/htdocs"
HOST_PUBLIC_HTML_DIR="${HOST_APACHE_DATA_DIR}/public_html"
HOST_LOGS_DIR="${HOST_APACHE_DATA_DIR}/logs" # Dla trwałych logów

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

# Sprawdzenie, czy kontener już istnieje i jego usunięcie
log_info "Sprawdzanie, czy kontener '${CONTAINER_NAME}' już istnieje..."
if sudo docker ps -a --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    log_info "Kontener '${CONTAINER_NAME}' już istnieje. Zatrzymuję i usuwam go..."
    sudo docker stop "${CONTAINER_NAME}" || log_error "Nie udało się zatrzymać kontenera '${CONTAINER_NAME}'."
    sudo docker rm "${CONTAINER_NAME}" || log_error "Nie udało się usunąć kontenera '${CONTAINER_NAME}'."
else
    log_info "Kontener '${CONTAINER_NAME}' nie istnieje. Kontynuuję."
fi

# Sprawdzenie, czy obraz już istnieje i jego usunięcie (opcjonalne, ale przydatne przy testach)
log_info "Sprawdzanie, czy obraz '${IMAGE_NAME}' już istnieje..."
if sudo docker images --format '{{.Repository}}' | grep -q "${IMAGE_NAME}"; then
    log_info "Obraz '${IMAGE_NAME}' już istnieje. Usuwam go, aby zbudować najnowszą wersję..."
    sudo docker rmi "${IMAGE_NAME}" || log_error "Nie udało się usunąć obrazu '${IMAGE_NAME}'. Upewnij się, że nie jest używany."
else
    log_info "Obraz '${IMAGE_NAME}' nie istnieje. Kontynuuję."
fi

# --- Tworzenie katalogów danych na hoście i wstępne pliki ---
log_info "Tworzenie katalogów danych Apache na hoście: ${HOST_APACHE_DATA_DIR}"
mkdir -p "${HOST_HTDOCS_DIR}" || log_error "Nie udało się utworzyć ${HOST_HTDOCS_DIR}."
mkdir -p "${HOST_PUBLIC_HTML_DIR}" || log_error "Nie udało się utworzyć ${HOST_PUBLIC_HTML_DIR}."
mkdir -p "${HOST_LOGS_DIR}" || log_error "Nie udało się utworzyć ${HOST_LOGS_DIR}."

log_info "Ustawianie uprawnień dla katalogów danych na hoście..."
# Ważne: Uprawnienia muszą pozwolić użytkownikowi apacheuser w kontenerze na dostęp
sudo chmod 755 "${HOST_APACHE_DATA_DIR}" "${HOST_HTDOCS_DIR}" "${HOST_PUBLIC_HTML_DIR}" "${HOST_LOGS_DIR}" || log_error "Nie udało się ustawić uprawnień dla katalogów danych na hoście."
# Zapewnienie, że apacheuser może pisać do logów (jeśli to jest na hoście)
# W tym przypadku logi Apache'a są domyślnie tworzone w ${APACHE_HOME}/logs w kontenerze.
# Jeśli chcemy, aby logi trafiały do HOST_LOGS_DIR, musimy go zamontować
# i upewnić się, że użytkownik Apache w kontenerze ma do niego prawo zapisu.
# Domyślnie Apache jest skonfigurowany do zapisu logów w ${APACHE_HOME}/logs.
# Będziemy montować ${HOST_LOGS_DIR} do ${APACHE_HOME}/logs.

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

# Uruchomienie kontenera z woluminami
log_info "Uruchamiam kontener '${CONTAINER_NAME}' na portach 80 i 443 z zamontowanymi woluminami..."
sudo docker run -d \
    -p 80:80 \
    -p 443:443 \
    -v "${HOST_HTDOCS_DIR}":"${APACHE_HOME_CONTAINER}/htdocs" \
    -v "${HOST_PUBLIC_HTML_DIR}":"/home/apacheuser/public_html" \
    -v "${HOST_LOGS_DIR}":"${APACHE_HOME_CONTAINER}/logs" \
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
log_info "Wszelkie zmiany w plikach na hoście w katalogach:"
log_info "  - ${HOST_HTDOCS_DIR}"
log_info "  - ${HOST_PUBLIC_HTML_DIR}"
log_info "Będą natychmiast widoczne w kontenerze!"
log_info "Logi Apache'a znajdziesz na hoście w: ${HOST_LOGS_DIR}"
log_info "Jeśli chcesz zatrzymać kontener: 'sudo docker stop ${CONTAINER_NAME}'"
log_info "Jeśli chcesz usunąć kontener: 'sudo docker rm ${CONTAINER_NAME}'"