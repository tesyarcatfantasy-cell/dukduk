package main

import (
	"database/sql"
	"fmt"

	_ "github.com/duckdb/duckdb-go/v2"
)

func main() {

	extpath := "../duckdblib/extension/postgres_scanner/postgres_scanner.duckdb_extension"
	xlsExtPath := "../duckdblib/extension/excel/excel.duckdb_extension"
	arrowExtPath := "../duckdblib/extension/nanoarrow/nanoarrow.duckdb_extension"

	extensions := []string{
		extpath,
		xlsExtPath,
		arrowExtPath,
	}

	// duck, err := db.InitDuck(":memory:?allow_unsigned_extensions=true",
	// 	db.AttachPostgres(extpath, os.Getenv("DSN"), true),
	// 	db.LoadExtensions(xlsExtPath), db.LoadExtensions(arrowExtPath))
	// if err != nil {
	// 	panic(err)
	// }
	// defer duck.Close()

	// fmt.Println(os.Getenv("DSN"))

	// q := `
	// COPY (SELECT * FROM worksheet.worksheet.analize) TO 'test.xlsx' WITH (FORMAT xlsx, HEADER true);
	// `

	// rows, err := duck.QueryContext(context.Background(), q)
	// if err != nil {
	// 	panic(err)
	// }

	// defer rows.Close()

	// var tblName string

	// for rows.Next() {
	// 	err = rows.Scan(&tblName)
	// 	if err != nil {
	// 		panic(err)
	// 	}

	// 	fmt.Println("tbl", tblName)
	// }

	db, err := sql.Open("duckdb", ":memory:?allow_unsigned_extensions=true")

	if err != nil {
		panic(err)
	}

	defer db.Close()

	for _, extPath := range extensions {
		if _, err := db.Exec(fmt.Sprintf(`LOAD '%s';`, extPath)); err != nil {
			panic(err)
		}

		fmt.Println("success init ext", extPath)

	}

}
