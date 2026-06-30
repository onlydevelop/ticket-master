package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// testPool connects to a real Postgres instance.
// Set TEST_DATABASE_URL in the environment (CI does this via services:).
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestGetEvent_NotFound(t *testing.T) {
	pool := testPool(t)

	r := chi.NewRouter()
	r.Get("/events/{id}", getEvent(pool))

	req := httptest.NewRequest(http.MethodGet, "/events/00000000-0000-0000-0000-000000000000", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

func TestSearchEvents_MissingQuery(t *testing.T) {
	pool := testPool(t)

	r := chi.NewRouter()
	r.Get("/events/search", searchEvents(pool))

	req := httptest.NewRequest(http.MethodGet, "/events/search", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", w.Code)
	}
}

func TestSearchEvents_ReturnsJSON(t *testing.T) {
	pool := testPool(t)

	r := chi.NewRouter()
	r.Get("/events/search", searchEvents(pool))

	req := httptest.NewRequest(http.MethodGet, "/events/search?q=concert", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}

	var result []Event
	if err := json.NewDecoder(w.Body).Decode(&result); err != nil {
		t.Fatalf("decode response: %v", err)
	}
}
