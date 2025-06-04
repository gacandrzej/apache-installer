# Używamy oficjalnego obrazu Ubuntu 22.04 jako bazy
FROM ubuntu:22.04

# Ustawiamy zmienne środowiskowe
ENV DEBIAN_FRONTEND=noninteractive
ENV APACHE_USER apacheuser
ENV APACHE_GROUP apachegroup
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

# Tworzenie katalogów Apache (bez htdocs, public_html, conf, logs, bo będą montowane)
# Pozostawiamy conf/ssl, bo certyfikaty są generowane w obrazie
RUN mkdir -p ${APACHE_HOME}/conf/ssl

# Tworzenie dedykowanej grupy i użytkownika dla Apache'a
RUN groupadd ${APACHE_GROUP} && \
    useradd -r -s /bin/false -g ${APACHE_GROUP} ${APACHE_USER}

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

# Generowanie samodzielnie podpisanego certyfikatu SSL (zostaje w obrazie)
RUN openssl genrsa -out ${APACHE_HOME}/conf/ssl/server.key 2048 && \
    chmod 600 ${APACHE_HOME}/conf/ssl/server.key && \
    openssl req -x509 -new -nodes -key ${APACHE_HOME}/conf/ssl/server.key \
        -sha256 -days 365 -out ${APACHE_HOME}/conf/ssl/server.crt \
        -subj "/C=PL/ST=Kujawsko-Pomorskie/L=Toruń/O=ZSMEiE/OU=IT/CN=${COMMON_NAME}/emailAddress=admin@zsmeie.pl"

# !!! WAŻNE !!!
# Usunięto modyfikacje plików konfiguracyjnych Apache'a (httpd.conf, httpd-ssl.conf, httpd-userdir.conf)
# Te pliki będą dostarczane z hosta poprzez montowanie woluminów.
# Obraz Apache będzie zawierał jedynie oryginalne, "czyste" pliki konfiguracyjne po instalacji.

# Czyszczenie plików źródłowych i tymczasowych po kompilacji
RUN rm -rf /tmp/src

# Otwarcie portów w kontenerze
EXPOSE 80 443

# Definiowanie entrypoint.sh (skrypt startowy)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]