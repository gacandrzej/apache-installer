# Używamy oficjalnego obrazu Ubuntu 22.04 jako bazy
FROM ubuntu:22.04

# Ustawiamy zmienne środowiskowe
ENV DEBIAN_FRONTEND=noninteractive
ENV APACHE_USER www-data
ENV APACHE_GROUP www-data
ENV APACHE_HOME /usr/local/apache2
ENV APACHE_VERSION 2.4.63
ENV APACHE_TARBALL httpd-${APACHE_VERSION}.tar.bz2
ENV APACHE_URL https://downloads.apache.org/httpd/${APACHE_TARBALL}
ENV APACHE_ASC_URL https://downloads.apache.org/httpd/${APACHE_TARBALL}.asc
ENV APACHE_SHA256_URL https://downloads.apache.org/httpd/${APACHE_TARBALL}.sha256
ENV APACHE_GPG_KEY_ID E33D83D62932EDEF
ENV COMMON_NAME zsmeie

# Ustawiamy katalog roboczy dla pobierania i kompilacji
WORKDIR /tmp/src

# Aktualizacja listy pakietów i instalacja wymaganych zależności
RUN apt update && \
    apt install -y --no-install-recommends \
        openssl \
        build-essential \
        libapr1-dev \
        libaprutil1-dev \
        libpcre3-dev \
        libpcre3 \
        libssl-dev \
        wget \
        curl \
        gnupg \
        procps \
        net-tools && \
    rm -rf /var/lib/apt/lists/*

# Dodawanie użytkownika 'marek' i ustawienie jego katalogu domowego
# Używamy -m (tworzy katalog domowy) i -d (określa ścieżkę)
# -N oznacza, że nie tworzymy dedykowanej grupy 'marek'. Użytkownik zostanie dodany do grupy domyślnej.
# -G www-data: Dodajemy 'marek' do grupy 'www-data', aby Apache (działający jako www-data) miał dostęp do plików.
# -s /bin/bash: Domyślna powłoka (przydatne do debugowania).
RUN useradd -r -N -m -d /home/marek -G www-data -s /bin/bash marek && \
    mkdir -p /home/marek/public_html && \
    chown -R marek:www-data /home/marek && \
    chmod -R 755 /home/marek/public_html

# Opcjonalnie: Ustawienie domyślnej zawartości dla public_html Marka
#COPY ./public_html_marek_default/ /home/marek/public_html/

# Tworzenie katalogów Apache (bez htdocs, public_html, conf, logs, bo będą montowane)
# Pozostawiamy conf/ssl, bo certyfikaty są generowane w obrazie
RUN mkdir -p ${APACHE_HOME}/conf/ssl

# Pobieranie źródeł Apache
RUN wget --no-check-certificate ${APACHE_URL} && \
    wget --no-check-certificate ${APACHE_ASC_URL} && \
    curl --insecure -sO ${APACHE_SHA256_URL}

# Weryfikacja sum kontrolnych i import klucza GPG
RUN sha256sum -c ${APACHE_TARBALL}.sha256 || exit 1
COPY stefan_eissing_public.asc /tmp/apache_signer_key.asc
# Zaimportuj klucz GPG Stefana Eissinga
RUN gpg --batch --import /tmp/apache_signer_key.asc && \
    # Opcjonalnie: Usuń plik klucza po zaimportowaniu, aby zmniejszyć rozmiar obrazu
    rm /tmp/apache_signer_key.asc
#RUN gpg --keyserver pgp.mit.edu --recv-keys ${APACHE_GPG_KEY_ID} || exit 1
#RUN gpg --verify ${APACHE_TARBALL}.asc ${APACHE_TARBALL} || exit 1

# Rozpakowanie i kompilacja Apache'a
RUN tar xjf ${APACHE_TARBALL} && \
    cd httpd-${APACHE_VERSION} && \
    ./configure \
        --prefix=${APACHE_HOME} \
        --with-ssl \
        --enable-ssl \
        --enable-so \
        --enable-authz-host \
        --enable-rewrite \
        --enable-userdir \
        --with-mpm=prefork && \
    make -j$(nproc) && \
    make install

# omówienie z klasą 2k
# omówienie z klasą 2GT

# Generowanie samodzielnie podpisanego certyfikatu SSL (zostaje w obrazie)
#RUN openssl genrsa -out ${APACHE_HOME}/conf/ssl/server.key 2048 && \
#    chmod 600 ${APACHE_HOME}/conf/ssl/server.key && \
#    openssl req -x509 -new -nodes -key ${APACHE_HOME}/conf/ssl/server.key \
#        -sha256 -days 365 -out ${APACHE_HOME}/conf/ssl/server.crt \
#        -subj "/C=PL/ST=Kujawsko-Pomorskie/L=Toruń/O=ZSMEiE/OU=IT/CN=${COMMON_NAME}/emailAddress=admin@zsmeie.pl"


# Czyszczenie plików źródłowych i tymczasowych po kompilacji
RUN rm -rf /tmp/src

# Otwarcie portów w kontenerze
EXPOSE 80 443

# Definiowanie entrypoint.sh (skrypt startowy)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's#exec "$@"#exec "$@" || echo "Apache failed to start. Check command/config." && exit 1#' /usr/local/bin/entrypoint.sh
# To modyfikuje entrypoint tak, by wyświetlił komunikat i zakończył się z błędem, jeśli główna komenda zawiedzie.

# Możesz również dodać więcej `set -x` w entrypoint.sh dla bardziej szczegółowych logów.
RUN sed -i '1s/^/#!\/bin\/bash\nset -ex\n/' /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]