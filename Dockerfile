# Używamy oficjalnego obrazu Ubuntu 22.04 jako bazy
FROM ubuntu:22.04

# Ustawiamy zmienne środowiskowe
ENV DEBIAN_FRONTEND=noninteractive
ENV APACHE_USER apacheuser  # Nowy użytkownik Apache'a
ENV APACHE_GROUP apachegroup # Nowa grupa Apache'a
ENV APACHE_HOME /usr/local/apache2
ENV APACHE_VERSION 2.4.63
ENV APACHE_TARBALL httpd-${APACHE_VERSION}.tar.bz2
ENV APACHE_URL https://dlcdn.apache.org/httpd/${APACHE_TARBALL}
ENV APACHE_ASC_URL https://downloads.apache.org/httpd/${APACHE_VERSION}/${APACHE_TARBALL}.asc
ENV APACHE_SHA256_URL https://downloads.apache.org/httpd/${APACHE_VERSION}/${APACHE_TARBALL}.sha256
ENV APACHE_GPG_KEY_ID E33D83D62932EDEF
ENV COMMON_NAME zsmeie

# Ustawiamy katalog roboczy dla pobierania i kompilacji
WORKDIR /tmp/src

# Aktualizacja listy pakietów i instalacja wymaganych zależności
# procps i net-tools dla narzedzi diagnostycznych jak ps, netstat, ss
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

# Tworzenie katalogów Apache
RUN mkdir -p ${APACHE_HOME}/conf/ssl && \
    mkdir -p ${APACHE_HOME}/logs && \
    mkdir -p ${APACHE_HOME}/htdocs

# Tworzenie dedykowanej grupy i użytkownika dla Apache'a
RUN groupadd ${APACHE_GROUP} && \
    useradd -r -s /bin/false -g ${APACHE_GROUP} ${APACHE_USER}

# Pobieranie źródeł Apache
RUN wget ${APACHE_URL} && \
    wget ${APAPE_ASC_URL} && \
    curl -sO ${APAPE_SHA256_URL}

# Weryfikacja sum kontrolnych i import klucza GPG
RUN sha256sum -c ${APACHE_TARBALL}.sha256 || exit 1
RUN gpg --keyserver keyserver.ubuntu.com --recv-keys ${APACHE_GPG_KEY_ID} --batch --yes || exit 1
RUN gpg --verify ${APACHE_TARBALL}.asc ${APACHE_TARBALL} || exit 1

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

# Generowanie samodzielnie podpisanego certyfikatu SSL
# Klucz i certyfikat będą w katalogu conf/ssl
RUN openssl genrsa -out ${APACHE_HOME}/conf/ssl/server.key 2048 && \
    chmod 600 ${APACHE_HOME}/conf/ssl/server.key && \
    openssl req -x509 -new -nodes -key ${APACHE_HOME}/conf/ssl/server.key \
        -sha256 -days 365 -out ${APACHE_HOME}/conf/ssl/server.crt \
        -subj "/C=PL/ST=Kujawsko-Pomorskie/L=Toruń/O=ZSMEiE/OU=IT/CN=${COMMON_NAME}/emailAddress=admin@zsmeie.pl"

# Konfiguracja Apache'a (httpd.conf)
# Zmieniamy użytkownika i grupę, pod którymi działa Apache
RUN sed -i "s/^User daemon/User ${APACHE_USER}/" ${APACHE_HOME}/conf/httpd.conf && \
    sed -i "s/^Group daemon/Group ${APACHE_GROUP}/" ${APACHE_HOME}/conf/httpd.conf && \
    sed -i 's/^#LoadModule ssl_module modules\/mod_ssl.so/LoadModule ssl_module modules\/mod_ssl.so/' ${APACHE_HOME}/conf/httpd.conf && \
    sed -i 's/^#Include conf\/extra\/httpd-ssl.conf/Include conf\/extra\/httpd-ssl.conf/' ${APACHE_HOME}/conf/httpd.conf && \
    sed -i 's/^#LoadModule userdir_module modules\/mod_userdir.so/LoadModule userdir_module modules\/mod_userdir.so/' ${APACHE_HOME}/conf/httpd.conf && \
    sed -i 's/^#Include conf\/extra\/httpd-userdir.conf/Include conf\/extra\/httpd-userdir.conf/' ${APACHE_HOME}/conf/httpd.conf

# Konfiguracja httpd-ssl.conf
RUN sed -i "s|DocumentRoot \".*\"|DocumentRoot \"${APACHE_HOME}/htdocs\"|" ${APACHE_HOME}/conf/extra/httpd-ssl.conf && \
    sed -i "s|ServerName www.example.com:443|ServerName ${COMMON_NAME}:443|" ${APACHE_HOME}/conf/extra/httpd-ssl.conf && \
    sed -i "s|ServerAdmin you@example.com|ServerAdmin admin@zsmeie.pl|" ${APACHE_HOME}/conf/extra/httpd-ssl.conf && \
    sed -i "s|SSLCertificateFile \".*\"|SSLCertificateFile \"${APACHE_HOME}/conf/ssl/server.crt\"|" ${APACHE_HOME}/conf/extra/httpd-ssl.conf && \
    sed -i "s|SSLCertificateKeyFile \".*\"|SSLCertificateKeyFile \"${APACHE_HOME}/conf/ssl/server.key\"|" ${APACHE_HOME}/conf/extra/httpd-ssl.conf

# Konfiguracja httpd-userdir.conf
# Zmieniamy domyślny katalog public_html na /home/apacheuser/public_html
# Upewnij się, że UserDir jest ustawiony na "public_html" i AllowOverride All dla katalogu public_html
# Tworzymy też fizyczny katalog dla użytkownika Apache'a
RUN sed -i 's/^UserDir public_html/UserDir public_html/' ${APACHE_HOME}/conf/extra/httpd-userdir.conf && \
    sed -i '/<Directory "\/home\/user\/public_html">/,/<\/Directory>/s|Require all denied|Require all granted|' ${APACHE_HOME}/conf/extra/httpd-userdir.conf && \
    sed -i '/<Directory "\/home\/user\/public_html">/,/<\/Directory>/s|AllowOverride None|AllowOverride All|' ${APAPE_HOME}/conf/extra/httpd-userdir.conf && \
    mkdir -p /home/${APACHE_USER}/public_html && \
    echo "<html><body><h1>Witaj na stronie uzytkownika Apache w kontenerze!</h1></body></html>" > /home/${APACHE_USER}/public_html/index.html && \
    chmod 755 /home/${APACHE_USER}/public_html && \
    chmod 751 /home/${APACHE_USER} && \
    chown -R ${APACHE_USER}:${APACHE_GROUP} /home/${APACHE_USER} # Właściciel katalogu domowego i public_html

# Czyszczenie plików źródłowych i tymczasowych po kompilacji
RUN rm -rf /tmp/src

# Otwarcie portów w kontenerze
EXPOSE 80 443

# Definiowanie entrypoint.sh (skrypt startowy)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
