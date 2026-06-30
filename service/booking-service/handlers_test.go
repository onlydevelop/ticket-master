package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

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

// seedTicket inserts the minimum rows needed for a reserve attempt and returns
// the ticket ID. It cleans up after the test.
func seedTicket(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()

	var venueID string
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO venues (name, city, country, capacity) VALUES ('Test Arena','Mumbai','IN',1000) RETURNING id`,
	).Scan(&venueID); err != nil {
		t.Fatalf("insert venue: %v", err)
	}

	var eventID string
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO events (venue_id, title, description, starts_at) VALUES ($1,'Test Event','desc',NOW()+interval'7 days') RETURNING id`,
		venueID,
	).Scan(&eventID); err != nil {
		t.Fatalf("insert event: %v", err)
	}

	var ticketID string
	if err := pool.QueryRow(context.Background(),
		`INSERT INTO tickets (event_id, section, row, seat, price_cents) VALUES ($1,'A','1','1',5000) RETURNING id`,
		eventID,
	).Scan(&ticketID); err != nil {
		t.Fatalf("insert ticket: %v", err)
	}

	t.Cleanup(func() {
		pool.Exec(context.Background(), `DELETE FROM bookings  WHERE ticket_id = $1`, ticketID)
		pool.Exec(context.Background(), `DELETE FROM tickets   WHERE id = $1`, ticketID)
		pool.Exec(context.Background(), `DELETE FROM events    WHERE id = $1`, eventID)
		pool.Exec(context.Background(), `DELETE FROM venues    WHERE id = $1`, venueID)
	})

	return ticketID
}

// TestReserve_NoConcurrentDoubleBooking is the key correctness test.
// It fires N goroutines all trying to reserve the same ticket and asserts
// exactly one succeeds (HTTP 200) while the rest receive HTTP 409.
func TestReserve_NoConcurrentDoubleBooking(t *testing.T) {
	pool := testPool(t)
	ticketID := seedTicket(t, pool)

	r := chi.NewRouter()
	r.Post("/bookings/reserve", reserve(pool))

	const goroutines = 20
	results := make([]int, goroutines)
	var wg sync.WaitGroup

	for i := range goroutines {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			body, _ := json.Marshal(reserveRequest{
				TicketID: ticketID,
				UserID:   "00000000-0000-0000-0000-" + zeroPad(idx),
			})
			req := httptest.NewRequest(http.MethodPost, "/bookings/reserve", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			r.ServeHTTP(w, req)
			results[idx] = w.Code
		}(i)
	}
	wg.Wait()

	successes := 0
	for _, code := range results {
		if code == http.StatusOK {
			successes++
		}
	}
	if successes != 1 {
		t.Fatalf("want exactly 1 successful reservation, got %d (codes: %v)", successes, results)
	}
}

func TestReserve_TicketNotFound(t *testing.T) {
	pool := testPool(t)

	r := chi.NewRouter()
	r.Post("/bookings/reserve", reserve(pool))

	body, _ := json.Marshal(reserveRequest{
		TicketID: "00000000-0000-0000-0000-000000000000",
		UserID:   "00000000-0000-0000-0000-000000000001",
	})
	req := httptest.NewRequest(http.MethodPost, "/bookings/reserve", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("want 404, got %d", w.Code)
	}
}

func zeroPad(n int) string {
	s := "000000000000"
	d := []byte(s)
	for i := len(d) - 1; n > 0; i-- {
		d[i] = byte('0' + n%10)
		n /= 10
	}
	return string(d)
}
