# Buildstage
FROM ghcr.io/linuxserver/baseimage-alpine:3.15 as buildstage

# set NZBGET version
ARG NZBGET_RELEASE

RUN \
  echo "**** install build packages ****" && \
  apk add \
    curl \
    g++ \
    gcc \
    git \
    libxml2-dev \
    libxslt-dev \
    make \
    ncurses-dev \
    openssl-dev && \
  echo "**** build nzbget ****" && \
  if [ -z ${NZBGET_RELEASE+x} ]; then \
    NZBGET_RELEASE=$(curl -sX GET "https://api.github.com/repos/nzbget/nzbget/releases/latest" \
      | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  mkdir -p /app/nzbget && \
  git clone https://github.com/nzbget/nzbget.git nzbget && \
  cd nzbget/ && \
  git checkout ${NZBGET_RELEASE} && \
  git cherry-pick -n fa57474d && \
  ./configure \
    bindir='${exec_prefix}' && \
  make && \
  make prefix=/app/nzbget install && \
  sed -i \
    -e "s#^MainDir=.*#MainDir=/downloads#g" \
    -e "s#^ScriptDir=.*#ScriptDir=$\{AppDir\}/share/nzbget/scripts#g" \
    -e "s#^WebDir=.*#WebDir=$\{AppDir\}/webui#g" \
    -e "s#^ConfigTemplate=.*#ConfigTemplate=$\{AppDir\}/webui/nzbget.conf.template#g" \
    -e "s#^UnrarCmd=.*#UnrarCmd=$\{AppDir\}/unrar#g" \
    -e "s#^SevenZipCmd=.*#SevenZipCmd=$\{AppDir\}/7za#g" \
    -e "s#^CertStore=.*#CertStore=$\{AppDir\}/cacert.pem#g" \
    -e "s#^CertCheck=.*#CertCheck=yes#g" \
    -e "s#^DestDir=.*#DestDir=$\{MainDir\}/completed#g" \
    -e "s#^InterDir=.*#InterDir=$\{MainDir\}/intermediate#g" \
    -e "s#^LogFile=.*#LogFile=$\{MainDir\}/nzbget.log#g" \
    -e "s#^AuthorizedIP=.*#AuthorizedIP=127.0.0.1#g" \
    -e "s#^ControlPort=.*#ControlPort=7777#g" \
  /app/nzbget/share/nzbget/nzbget.conf && \
  mv /app/nzbget/share/nzbget/webui /app/nzbget/ && \
  cp /app/nzbget/share/nzbget/nzbget.conf /app/nzbget/webui/nzbget.conf.template && \
  ln -s /usr/bin/7za /app/nzbget/7za && \
  ln -s /usr/bin/unrar /app/nzbget/unrar && \
  cp /nzbget/pubkey.pem /app/nzbget/pubkey.pem && \
  curl -o \
    /app/nzbget/cacert.pem -L \
    "https://curl.haxx.se/ca/cacert.pem"

# Runtime Stage
FROM ghcr.io/linuxserver/baseimage-alpine:3.15

ARG UNRAR_VERSION=6.1.7
# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache --upgrade --virtual=build-dependencies \
    cargo \
    g++ \
    gcc \
    libc-dev \
    libffi-dev \
    libxml2-dev \
    libxslt-dev \
    make \
    openssl-dev \
    python3-dev && \
  echo "**** install packages ****" && \
  apk add --no-cache \
    curl \
    libxml2 \
    libxslt \
    openssl \
    p7zip \
    py3-pip \
    python3 \
    wget && \
  echo "**** install unrar from source ****" && \
  mkdir /tmp/unrar && \
  curl -o \
    /tmp/unrar.tar.gz -L \
    "https://www.rarlab.com/rar/unrarsrc-${UNRAR_VERSION}.tar.gz" && \  
  tar xf \
    /tmp/unrar.tar.gz -C \
    /tmp/unrar --strip-components=1 && \
  cd /tmp/unrar && \
  make && \
  install -v -m755 unrar /usr/bin && \
  echo "**** install python packages ****" && \
  pip3 install --no-cache-dir -U \
    pip && \
  pip install --no-cache-dir --find-links https://wheel-index.linuxserver.io/alpine/ \
    apprise \
    chardet \
    lxml \
    py7zr \
    pynzbget \
    rarfile \
    six && \
  ln -s /usr/bin/python3 /usr/bin/python && \
  echo "**** cleanup ****" && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    /root/.cache \
    /root/.cargo \
    /tmp/*

# add local files and files from buildstage
COPY --from=buildstage /app/nzbget /app/nzbget
COPY root/ /

# ports and volumes
VOLUME /config
EXPOSE 7777

RUN \
echo "**** install extra packages ****" && \
  apk add --no-cache \
    git \
    ffmpeg && \
    #git clone https://github.com/clinton-hall/nzbToMedia.git /app/nzbget/share/nzbget/scripts/nzbToMedia && \
    echo "**** par2cmdline compile ****" && \
    apk add build-base automake autoconf python3 libgomp git && \
    wget -O- https://github.com/Parchive/par2cmdline/archive/v0.8.1.tar.gz | tar -zx && \
    cd par2cmdline-0.8.1 && \
    aclocal && \
    automake --add-missing && \
    autoconf && \
    ./configure  && \
    make && \
    make install && \
    ln -s /usr/local/bin/par2 /app/nzbget/par2 && \
    cd .. && \
    rm -rf par2cmdline-0.8.1 && \
    apk del build-base automake autoconf \