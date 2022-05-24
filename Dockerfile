# global args
ARG __BUILD_DIR__="/build"
ARG __DATA_DIR__="/data"
ARG REDIS_VERSION="7.0.0"



FROM fscm/centos:stream as build

ARG __BUILD_DIR__
ARG __DATA_DIR__
ARG __WORK_DIR__="/work"
ARG REDIS_VERSION
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
    #export DCACHE_LINESIZE="$(getconf LEVEL1_DCACHE_LINESIZE || echo 64)" && \
    export DCACHE_LINESIZE="64" && \
    export __KARCH__="$(case `arch` in x86_64*) echo x86;; aarch64) echo arm64;; esac)" && \
    export __MARCH__="$(case `arch` in x86_64*) echo x86-64;; aarch64) echo armv8-a;; esac)" && \
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
        perl-base \
        perl-interpreter \
        perl-lib \
        perl-open \
        perl-File-Compare \
        perl-File-Copy \
        perl-FindBin \
        perl-IPC-Cmd \
        rsync \
        tar \
        which \
        xz \
        > /dev/null && \
# kernel headers
    echo '--> installing kernel headers' && \
    KERNEL_VERSION="$(curl --silent --location --retry 3 'https://www.kernel.org/releases.json' | jq -r '.latest_stable.version')" && \
    install --directory "${__SOURCE_DIR__}/kernel" && \
    curl --silent --location --retry 3 "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/linux-${KERNEL_VERSION}.tar.xz" \
        | tar xJ --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/kernel" && \
    cd "${__SOURCE_DIR__}/kernel" && \
    make mrproper > /dev/null && \
    make ARCH="${__KARCH__}" INSTALL_HDR_PATH="/usr/local" headers_install > /dev/null && \
    # The kernel headers that exported to user space are not covered by the GPLv2 license.
    # This is documented in the "Linux kernel licensing rules":
    # https://www.kernel.org/doc/html/latest/process/license-rules.html
    cd ~- && \
    rm -rf "${__SOURCE_DIR__}/kernel" && \
# musl
    echo '--> installing musl libc' && \
    install --directory "${__SOURCE_DIR__}/musl/_build" && \
    curl --silent --location --retry 3 "https://musl.libc.org/releases/musl-latest.tar.gz" \
        | tar xz --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/musl" && \
    cd "${__SOURCE_DIR__}/musl/_build" && \
    ../configure \
        CFLAGS="-fPIC -O2 -g0 -s -w -pipe -march=${__MARCH__} -mtune=generic -DNDEBUG -DCLS=${__DCACHE_LINESIZE__}" \
        --prefix='/usr/local' \
        --disable-debug \
        --disable-shared \
        --enable-wrapper=all \
        --enable-static \
        > /dev/null && \
    make > /dev/null && \
    make install > /dev/null && \
    # Applications linked against all musl public header files and crt files are allowed to
    # omit copyright notice and permission notice otherwise required by the license.
    # This is documented in the "COPYRIGHT" file.
    # https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
    cd ~- && \
    rm -rf "${__SOURCE_DIR__}/musl" && \
# zlib
    echo '--> installing zlib' && \
    ZLIB_VERSION="$(rpm -q --qf "%{VERSION}" zlib)" && \
    install --directory "${__SOURCE_DIR__}/zlib/_build" && \
    curl --silent --location --retry 3 "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" \
        | tar xz --no-same-owner --strip-components=1 -C "${__SOURCE_DIR__}/zlib" && \
    cd "${__SOURCE_DIR__}/zlib/_build" && \
    sed -i.orig -e '/(man3dir)/d' ../Makefile.in && \
    CC="musl-gcc -static --static" \
    CFLAGS="-fPIC -O2 -g0 -s -w -pipe -mmusl -march=${__MARCH__} -mtune=generic -DNDEBUG -DCLS=${__DCACHE_LINESIZE__}" \
    ../configure \
        --prefix='/usr/local' \
        --includedir='/usr/local/include' \
        --libdir='/usr/local/lib' \
        --static \
        > /dev/null && \
    make > /dev/null && \
    make install > /dev/null && \
    install --directory --owner="${__USER__}" --group="${__USER__}" --mode=0755 "${__BUILD_DIR__}/licenses/zlib" && \
    install --owner="${__USER__}" --group="${__USER__}" --mode=0644 --target-directory="${__BUILD_DIR__}/licenses/zlib" '../README' && \
    (cd .. && find ./ -type f -a \( -iname '*LICENSE*' -o -iname '*COPYING*' \) -exec cp --parents {} "${__BUILD_DIR__}/licenses/zlib" ';') && \
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
        -static \
        -DCLS=${DCACHE_LINESIZE} \
        -DNDEBUG \
        -DOPENSSL_NO_HEARTBEATS \
        -fPIC -O2 -g0 -s -w -pipe -mmusl -march=${__MARCH__} -mtune=generic '-DDEVRANDOM="\"/dev/urandom\""' && \
    make > /dev/null && \
    make install_sw > /dev/null && \
    make install_ssldirs > /dev/null && \
    install --directory --owner="${__USER__}" --group="${__USER__}" --mode=0755 "${__BUILD_DIR__}/licenses/openssl" && \
    (cd .. && find ./ -type f -a \( -iname '*LICENSE*' -o -iname '*COPYING*' \) -exec cp --parents {} "${__BUILD_DIR__}/licenses/openssl" ';') && \
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
        CFLAGS="-fPIC -O2 -g0 -s -w -pipe -mmusl -march=${__MARCH__} -mtune=generic -DCLS=${__DCACHE_LINESIZE__}" \
        BUILD_TLS="yes" \
        > /dev/null && \
    make PREFIX="${__BUILD_DIR__}/usr" install > /dev/null && \
    install --directory --owner="${__USER__}" --group="${__USER__}" --mode=0755 "${__BUILD_DIR__}/licenses/redis" && \
    install --owner="${__USER__}" --group="${__USER__}" --mode=0644 --target-directory="${__BUILD_DIR__}/licenses/redis" './COPYING' && \
    find ./ -type f -a \( -iname '*LICENSE*' -o -iname '*COPYING*' \) -exec cp --parents {} "${__BUILD_DIR__}/licenses/redis" ';' && \
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
ARG REDIS_VERSION

LABEL \
    maintainer="Frederico Martins <https://hub.docker.com/u/fscm/>" \
    vendor="fscm" \
    cmd="docker container run --detach --publish 6379:6379/tcp fscm/redis server" \
    params="--volume $$PWD:${__DATA_DIR__}:rw" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.name="fscm/redis" \
    org.label-schema.description="A small Redis image that can be used to start a Redis server" \
    org.label-schema.url="https://redis.io/" \
    org.label-schema.vcs-url="https://github.com/fscm/docker-redis/" \
    org.label-schema.vendor="fscm" \
    org.label-schema.version=${REDIS_VERSION} \
    org.label-schema.docker.cmd="docker container run --detach --rm --publish 6379:6379/tcp fscm/redis server" \
    org.label-schema.docker.cmd.test="docker container run --detach --rm --publish 6379:6379/tcp fscm/redis server --version" \
    org.label-schema.docker.params="--volume $$PWD:${__DATA_DIR__}:rw"

EXPOSE 6379/tcp

COPY --from=build "${__BUILD_DIR__}" "/"

VOLUME ["${__DATA_DIR__}"]

WORKDIR "${__DATA_DIR__}"

ENV DATA_DIR="${__DATA_DIR__}"
