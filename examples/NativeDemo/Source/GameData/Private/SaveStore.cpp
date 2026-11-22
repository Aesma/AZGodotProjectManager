#include "SaveStore.hpp"

#include <sqlite3.h>

int SaveStore::read_demo_score() {
    sqlite3 *db = nullptr;
    sqlite3_stmt *query = nullptr;
    int score = -1;
    const char *sql = "WITH save_slot(score) AS (VALUES (42)) SELECT score FROM save_slot";
    if (sqlite3_open(":memory:", &db) == SQLITE_OK &&
            sqlite3_prepare_v2(db, sql, -1, &query, nullptr) == SQLITE_OK &&
            sqlite3_step(query) == SQLITE_ROW) {
        score = sqlite3_column_int(query, 0);
    }
    sqlite3_finalize(query);
    sqlite3_close(db);
    return score;
}
