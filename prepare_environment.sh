#!/bin/bash

# Funkcje do logowania
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo -e "\n[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $1\n"
}

log_error() {
    echo -e "\n[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1\n" >&2
    exit 1
}

# --- Rozpoczęcie przygotowywania środowiska ---
log_info "Rozpoczynam przygotowywanie środowiska pracy dla projektu Apache Docker Compose."

# 1. Sprawdzenie i instalacja Git
log_info "Sprawdzam instalację Git..."
if ! command -v git &> /dev/null; then
    log_info "Git nie znaleziony. Instaluję Git..."
    sudo apt update || log_error "Nie udało się zaktualizować list pakietów APT."
    sudo apt install -y git || log_error "Nie udało się zainstalować Git. Sprawdź połączenie z internetem lub uprawnienia."
else
    log_info "Git jest już zainstalowany."
fi

# 2. Sprawdzenie i instalacja OpenSSL
log_info "Sprawdzam instalację OpenSSL..."
if ! command -v openssl &> /dev/null; then
    log_info "OpenSSL nie znaleziony. Instaluję OpenSSL..."
    sudo apt update || log_error "Nie udało się zaktualizować list pakietów APT."
    sudo apt install -y openssl || log_error "Nie udało się zainstalować OpenSSL. Sprawdź połączenie z internetem lub uprawnienia."
else
    log_info "OpenSSL jest już zainstalowany."
fi

# 3. Sprawdzenie i instalacja Dockera
log_info "Sprawdzam instalację Dockera..."
if ! command -v docker &> /dev/null; then
    log_info "Docker nie znaleziony. Instaluję Dockera..."
    # Oficjalna metoda instalacji Dockera (zalecana)
    sudo apt update || log_error "Nie udało się zaktualizować list pakietów APT."
    sudo apt install -y ca-certificates curl gnupg || log_error "Nie udało się zainstalować wymaganych pakietów dla Dockera."

    sudo install -m 0755 -d /etc/apt/keyrings || log_error "Nie udało się utworzyć katalogu /etc/apt/keyrings."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || log_error "Nie udało się pobrać klucza GPG Dockera."
    sudo chmod a+r /etc/apt/keyrings/docker.gpg || log_error "Nie udało się ustawić uprawnień dla klucza GPG Dockera."

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || log_error "Nie udało się dodać repozytorium Dockera."

    sudo apt update || log_error "Nie udało się zaktualizować list pakietów APT po dodaniu repozytorium Dockera."
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || log_error "Nie udało się zainstalować Dockera i Docker Compose Plugin."

    log_info "Dodaję bieżącego użytkownika ($USER) do grupy docker. Wymaga to ponownego zalogowania się!"
    sudo usermod -aG docker "$USER" || log_error "Nie udało się dodać użytkownika do grupy docker."
    log_info "Po zakończeniu działania skryptu, wyloguj się i zaloguj ponownie, aby zmiany uprawnień weszły w życie."
else
    log_info "Docker jest już zainstalowany."
fi

# 4. Sprawdzenie uprawnień do skryptu install.sh
log_info "Sprawdzam uprawnienia dla skryptu install.sh..."
if [ ! -x "./install.sh" ]; then
    log_info "Nadaję uprawnienia do wykonywania dla install.sh..."
    chmod +x ./install.sh || log_error "Nie udało się nadać uprawnień do wykonywania dla install.sh."
else
    log_info "Skrypt install.sh ma już uprawnienia do wykonywania."
fi

log_success "Środowisko zostało przygotowane!"
log_info "Jeśli Docker został świeżo zainstalowany i/lub dodano Cię do grupy docker, WYLUGUJ SIĘ I ZALOGUJ PONOWNIE, aby zmiany uprawnień weszły w życie."
log_info "Następnie możesz uruchomić projekt za pomocą: sudo ./install.sh"