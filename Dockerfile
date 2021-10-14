# global args
ARG __BUILD_DIR__="/build"
ARG __DATA_DIR__="/data"
ARG __WORK_DIR__="/work"



FROM fscm/centos:stream as build

ARG __BUILD_DIR__
ARG __DATA_DIR__
ARG __WORK_DIR__
ARG REDIS_VERSION="6.2.6"
ARG __USER__="root"
ARG __SOURCE_DIR__="${__WORK_DIR__}/src"

ENV \
  LANG="C.UTF-8" \
  LC_ALL="C.UTF-8"

USER "${__USER__}"

COPY "LICENSE" "${__WORK_DIR__}"/

WORKDIR "${__WORK_DIR__}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN \
# build env
  echo '--> setting build env' && \
  set +h && \
  export __NPROC__="$(getconf _NPROCESSORS_ONLN || echo 1)" && \
  export DCACHE_LINESIZE="$(getconf LEVEL1_DCACHE_LINESIZE || echo 64)" && \
  export MAKEFLAGS="--silent --no-print-directory --jobs ${__NPROC__}" && \
  export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig && \
# build structure
  echo '--> creating build structure' && \
  for folder in 'bin'; do \
    install --directory --owner="${__USER__}" --group="${__USER__}" --mode=0755 "${__BUILD_DIR__}/usr/${folder}"; \
  done && \
  for folder in '/tmp' "${__DATA_DIR__}"; do \
    install --directory --owner="${__USER__}" --group="${__USER__}" --mode=1777 "${__BUILD_DIR__}${folder}"; \
  done && \
# dependencies
  echo '--> instaling dependencies' && \
  dnf --assumeyes --quiet --setopt=install_weak_deps='no' install \
    binutils \
    ca-certificates \
    curl \
    diffutils \
    file \
    findutils \
    gcc \
    gettext \
    gzip \
    jq \
    make \
    perl-autodie \
    perl-interpreter \
    perl-open \
    rsync \
    tar \
    xz \
    > /dev/null && \
# kernel headers
  echo '--> installing kernel headers' && \
  KERNEL_VERSION="$(curl --silent --location --retry 3 'https://www.kernel.org/releases.json' | jq -r '.latest_stable.version')" && \
  install --directory "${__SOURCE_DIR__}/kernel" && \
  curl --silent --location --retry 3 "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/linux-${KERNEL_VERSION}.tar.xz" \
    | tar xJ --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/kernel" $(echo linux-*/{Makefile,arch,include,scripts,tools,usr}) && \
  cd "${__SOURCE_DIR__}/kernel" && \
  make INSTALL_HDR_PATH="/usr/local" headers_install > /dev/null && \
  cd ~- && \
  rm -rf "${__SOURCE_DIR__}/kernel" && \
# musl
  echo '--> installing musl libc' && \
  install --directory "${__SOURCE_DIR__}/musl/_build" && \
  curl --silent --location --retry 3 "https://musl.libc.org/releases/musl-latest.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/musl" && \
  cd "${__SOURCE_DIR__}/musl/_build" && \
  ../configure \
    CFLAGS="-O2 -g0 -s -w -pipe -mtune=generic -DNDEBUG -DCLS=${DCACHE_LINESIZE}" \
    --prefix='/usr/local' \
    --disable-debug \
    --disable-shared \
    --enable-wrapper=all \
    --enable-static \
    > /dev/null && \
  make > /dev/null && \
  make install > /dev/null && \
  cd ~- && \
  rm -rf "${__SOURCE_DIR__}/musl" && \
# zlib
  echo '--> installing zlib' && \
  ZLIB_VERSION="$(rpm -q --qf "%{VERSION}" zlib)" && \
  install --directory "${__SOURCE_DIR__}/zlib/_build" && \
  curl --silent --location --retry 3 "https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/zlib" && \
  cd "${__SOURCE_DIR__}/zlib/_build" && \
  sed -i.orig -e '/(man3dir)/d' ../Makefile.in && \
  CC="musl-gcc -static --static" \
  CFLAGS="-O2 -g0 -s -w -pipe -mtune=generic -DNDEBUG -DCLS=${DCACHE_LINESIZE}" \
  ../configure \
    --prefix='/usr/local' \
    --includedir='/usr/local/include' \
    --libdir='/usr/local/lib' \
    --static \
    > /dev/null && \
  make > /dev/null && \
  make install > /dev/null && \
  cd ~- && \
  rm -rf "${__SOURCE_DIR__}/zlib" && \
# openssl
  echo '--> installing openssl' && \
  OPENSSL_VERSION="$(rpm -q --qf "%{VERSION}" openssl-libs)" && \
  install --directory "${__SOURCE_DIR__}/openssl/_build" && \
  curl --silent --location --retry 3 "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/openssl" && \
  cd "${__SOURCE_DIR__}/openssl/_build" && \
  ../config \
    CC="musl-gcc -static --static" \
    --openssldir='/etc/ssl' \
    --prefix='/usr/local' \
    --libdir='/usr/local/lib' \
    --release \
    --static \
    enable-cms \
    enable-ec_nistp_64_gcc_128 \
    enable-rfc3779 \
    no-comp \
    no-shared \
    no-ssl3 \
    no-weak-ssl-ciphers \
    zlib \
    -pipe \
    -static \
    -DCLS=${DCACHE_LINESIZE} \
    -DNDEBUG \
    -DOPENSSL_NO_HEARTBEATS \
    -O2 -g0 -s -w -pipe -m64 -mtune=generic '-DDEVRANDOM="\"/dev/urandom\""' && \
  make > /dev/null && \
  make install_sw > /dev/null && \
  make install_ssldirs > /dev/null && \
  cd ~- && \
  rm -rf "${__SOURCE_DIR__}/openssl" && \
# redis
  echo '--> installing redis' && \
  install --directory "${__SOURCE_DIR__}/redis" && \
  curl --silent --location --retry 3 "https://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/redis" && \
  cd "${__SOURCE_DIR__}/redis" && \
  sed -i.orig -e '/createBoolConfig.*protected-mode/ s/protected_mode, 1/protected_mode, 0/' ./src/config.c && \
  __arch__="$(arch)" && \
  __arch_pagesize__="$(rpm --eval '%{arm} %{ix86} x86_64 s390x')" && \
  eval "case '${__arch__}' in ${__arch_pagesize__// /|}) EXTRA_ARGS='--with-lg-page=12' ;; *) EXTRA_ARGS='--with-lg-page=16' ;; esac" && \
  EXTRA_ARGS="${EXTRA_ARGS} --with-lg-hugepage=21" && \
  sed -i.orig -e "/cd jemalloc \&\& \.\/configure/ s/configure/configure ${EXTRA_ARGS}/" ./deps/Makefile && \
  unset __arch__ __arch_pagesize__ EXTRA_ARGS && \
  make \
    PREFIX="/usr" \
    CC="musl-gcc -static --static" \
    CFLAGS="-O2 -g0 -s -w -pipe -mtune=generic -DNDEBUG -DCLS=${DCACHE_LINESIZE}" \
    BUILD_TLS="yes" \
    > /dev/null && \
  make PREFIX="${__BUILD_DIR__}/usr" install > /dev/null && \
  install --directory --owner="${__USER__}" --group="${__USER__}" --mode=0755 "${__BUILD_DIR__}/licenses/redis" && \
  install --owner="${__USER__}" --group="${__USER__}" --mode=0644 --target-directory="${__BUILD_DIR__}/licenses/redis" './COPYING' && \
  cd ~- && \
  rm -rf "${__SOURCE_DIR__}/redis" && \
# stripping
  echo '--> stripping binaries' && \
  find "${__BUILD_DIR__}"/usr/bin -type f -not -links +1 -exec strip --strip-all {} ';' && \
# symbolic links
  echo '--> replacing symbolic links' && \
  for s in $(find "${__BUILD_DIR__}"/usr/bin -type l); do \
    ln --force "$(readlink -m "${s}")" "${s}"; \
  done && \
# alt links
  echo '--> creating alternative links' && \
  install --directory --owner="${__USER__}" --group="${__USER__}" --mode=0755 "${__BUILD_DIR__}/usr/local/bin" && \
  for app in $(find /build/usr/bin/ -name 'redis-*'); do \
    ln --force "${app}" "${__BUILD_DIR__}"/usr/local/bin/"${app#*-}"; \
  done && \
# licenses
  echo '--> project licenses' && \
  install --owner="${__USER__}" --group="${__USER__}" --mode=0644 --target-directory="${__BUILD_DIR__}/licenses" "${__WORK_DIR__}/LICENSE" && \
# done
  echo '--> all done!'



FROM scratch

ARG __BUILD_DIR__
ARG __DATA_DIR__

LABEL \
  maintainer="Frederico Martins <https://hub.docker.com/u/fscm/>" \
  vendor="fscm" \
  cmd="docker container run --detach --publish 6379:6379/tcp fscm/redis server" \
  params="--volume ./:${__DATA_DIR__}:rw"

EXPOSE 6379/tcp

COPY --from=build "${__BUILD_DIR__}" "/"

VOLUME ["${__DATA_DIR__}"]

WORKDIR "${__DATA_DIR__}"

ENV DATA_DIR="${__DATA_DIR__}"
