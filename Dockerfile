FROM registry.suse.com/bci/gcc:14 as cmake-downloader

WORKDIR /src/

RUN curl -L https://github.com/Kitware/CMake/archive/refs/tags/v3.30.9.tar.gz | tar -xz

RUN ls

FROM registry.suse.com/bci/gcc:14 as duckdb-downloader

WORKDIR /src/

RUN curl -L https://github.com/duckdb/duckdb/archive/refs/tags/v1.4.0.tar.gz | tar -xz

FROM registry.suse.com/bci/gcc:14 as arrownanodownloader

WORKDIR /src/

RUN curl -L https://github.com/apache/arrow-nanoarrow/releases/download/apache-arrow-nanoarrow-0.7.0/apache-arrow-nanoarrow-0.7.0.tar.gz | tar xz

RUN zypper install -y libopenssl-3-devel git python3 zip unzip kernel-devel

COPY --from=cmake-downloader /src/CMake-3.30.9 /cmake/

WORKDIR /cmake/

RUN ls
RUN ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release
RUN make
RUN make install DESTDIR=/cmake-install

FROM registry.suse.com/bci/gcc:14 as duckdb-builder

RUN zypper install -y libopenssl-3-devel git python3 zip unzip kernel-devel

WORKDIR /src/

COPY --from=cmake-downloader /src/CMake-3.30.9 /cmake/

WORKDIR /cmake/

RUN ls
RUN ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release
RUN make
RUN make install

WORKDIR /src/

RUN git clone https://github.com/Microsoft/vcpkg.git && ./vcpkg/bootstrap-vcpkg.sh

ENV VCPKG_ROOT=/src/vcpkg

COPY --from=duckdb-downloader /src/duckdb-1.4.0/ /src/duckdb/

COPY ./extension_config_local.cmake duckdb/extension/extension_config_local.cmake

RUN cd duckdb && CMAKE_POLICY_VERSION_MINIMUM=3.5 make extension_configuration && CMAKE_POLICY_VERSION_MINIMUM=3.5 USE_MERGED_VCPKG_MANIFEST=1 VCPKG_TOOLCHAIN_PATH=../vcpkg/scripts/buildsystems/vcpkg.cmake EXTENSION_STATIC_BUILD=1 make bundle-library

FROM registry.suse.com/bci/gcc:14 as appbuilder

ARG TARGETARCH
RUN set -eux; \
		case "${TARGETARCH}" in \
			amd64|arm64) GO_ARCH="${TARGETARCH}" ;; \
			*) echo "Unsupported TARGETARCH: ${TARGETARCH}"; exit 1 ;; \
		esac; \
		curl -fsSL "https://go.dev/dl/go1.24.5.linux-${GO_ARCH}.tar.gz" -o go.tar.gz; \
		tar -C /usr/local -xzf go.tar.gz; \
		rm go.tar.gz
ENV PATH="$PATH:/usr/local/go/bin"

WORKDIR /app/


COPY --from=duckdb-builder /src/duckdb/build/release/**/**/*.a /app/duckdblib/
COPY --from=duckdb-builder /src/duckdb/build/release/**/**/**/**/*.a /app/duckdblib/
COPY --from=duckdb-builder /src/duckdb/build/release/**/*.a /app/duckdblib/
COPY --from=duckdb-builder /src/duckdb/build/release/*.a /app/duckdblib/
COPY --from=duckdb-builder /src/duckdb/build/release/extension/ /app/duckdb/extension/



COPY ./appgo/ .


RUN CGO_ENABLED=1 CPPFLAGS="-DDUCKDB_STATIC_BUILD" CGO_LDFLAGS="-L./duckdblib -lnanoarrow_extension -lnanoarrow -lnanoarrow_ipc -lflatccrt -lduckdb_fastpforlib -lduckdb_fmt -lduckdb_fsst -lduckdb_hyperloglog -lduckdb_mbedtls -lduckdb_miniz -lduckdb_pg_query -lduckdb_re2 -lduckdb_skiplistlib -lduckdb_utf8proc -lduckdb_yyjson -limdb -lduckdb_static -lduckdb_zstd -ljemalloc_extension -lparquet_extension -lstdc++ -lm -ldl -lminizip-ng -lcore_functions_extension -lz -lexcel_extension -lexpat" go build -tags=duckdb_use_static_lib ./duckdb-tester/main.go 

FROM registry.suse.com/bci/bci-base:15.7

COPY --from=appbuilder /app/main main-app
COPY --from=appbuilder /app/duckdblib/ /duckdblib/






