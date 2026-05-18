## dukduk

Duckdb things

Contain two things:

- Atmr OLAP experimentation
- appgo --> a testing application where we connect to postgres via duckdb
- Base dockerfile for binding between duckdb, GO and extensions (postgres and excel)

## Docker image why?

In BSIM, the external access was blocked. 
Our application (fincen-api) installs extension during pod startup. 

The resolution for this is to link all duckdb libraries need and the extensions to the go binary.

```
CGO_ENABLED=1 CPPFLAGS="-DDUCKDB_STATIC_BUILD" CGO_LDFLAGS="-L../ -lnanoarrow_extension -lflatccrt -lnanoarrow -lnanoarrow_ipc -lduckdb_fastpforlib -lduckdb_fmt -lduckdb_fsst -lduckdb_hyperloglog -lduckdb_mbedtls -lduckdb_miniz -lduckdb_pg_query -lduckdb_re2 -lduckdb_skiplistlib -lduckdb_utf8proc -lduckdb_yyjson -limdb -lduckdb_static -lduckdb_zstd -ljemalloc_extension -lparquet_extension -lstdc++ -lm -ldl -lcore_functions_extension" go build -tags=duckdb_use_static_lib ./duckdb-tester/main.go
```

The multi-platform build also emits static library bundles:

```bash
./scripts/build_multi_platform.sh
unzip artifacts/duckdb-static-libs-macos-arm64.zip
```

The zip extracts to `duckdblib/*.a` plus `build-info.txt`, so the extracted `duckdblib` directory can be passed directly with `-L./duckdblib`.

## Native DuckDB build (macOS/Linux)

To avoid linker mismatch (for example Linux `.a` files on macOS), build DuckDB artifacts natively on each runner/host:

```bash
chmod +x scripts/build_duckdb_native.sh
./scripts/build_duckdb_native.sh
```

The script outputs host-specific artifacts to `duckdblib/` and writes metadata in `duckdblib/build-info.txt`.

Use `build_duckdb_native_linux` and `build_duckdb_native_macos` jobs in `.gitlab-ci.yml` as a starting point for a build matrix.
