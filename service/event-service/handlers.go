package main

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Performer struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type Venue struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	City     string `json:"city"`
	Country  string `json:"country"`
	Capacity int    `json:"capacity"`
}

type Event struct {
	ID          string      `json:"id"`
	Title       string      `json:"title"`
	Description string      `json:"description"`
	StartsAt    string      `json:"starts_at"`
	Venue       Venue       `json:"venue"`
	Performers  []Performer `json:"performers"`
}

func getEvent(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")

		var e Event
		err := pool.QueryRow(r.Context(), `
			SELECT e.id, e.title, e.description, e.starts_at,
			       v.id, v.name, v.city, v.country, v.capacity
			FROM events e
			JOIN venues v ON v.id = e.venue_id
			WHERE e.id = $1
		`, id).Scan(
			&e.ID, &e.Title, &e.Description, &e.StartsAt,
			&e.Venue.ID, &e.Venue.Name, &e.Venue.City, &e.Venue.Country, &e.Venue.Capacity,
		)
		if err != nil {
			http.Error(w, "event not found", http.StatusNotFound)
			return
		}

		rows, err := pool.Query(r.Context(), `
			SELECT p.id, p.name
			FROM performers p
			JOIN event_performers ep ON ep.performer_id = p.id
			WHERE ep.event_id = $1
		`, id)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var p Performer
			if err := rows.Scan(&p.ID, &p.Name); err != nil {
				http.Error(w, "internal error", http.StatusInternalServerError)
				return
			}
			e.Performers = append(e.Performers, p)
		}
		if e.Performers == nil {
			e.Performers = []Performer{}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(e)
	}
}

func searchEvents(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := strings.TrimSpace(r.URL.Query().Get("q"))
		if q == "" {
			http.Error(w, "q parameter is required", http.StatusBadRequest)
			return
		}

		rows, err := pool.Query(r.Context(), `
			SELECT e.id, e.title, e.description, e.starts_at,
			       v.id, v.name, v.city, v.country, v.capacity
			FROM events e
			JOIN venues v ON v.id = e.venue_id
			WHERE e.search_vector @@ plainto_tsquery('english', $1)
			ORDER BY ts_rank(e.search_vector, plainto_tsquery('english', $1)) DESC
			LIMIT 50
		`, q)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		events := []Event{}
		for rows.Next() {
			var e Event
			if err := rows.Scan(
				&e.ID, &e.Title, &e.Description, &e.StartsAt,
				&e.Venue.ID, &e.Venue.Name, &e.Venue.City, &e.Venue.Country, &e.Venue.Capacity,
			); err != nil {
				http.Error(w, "internal error", http.StatusInternalServerError)
				return
			}
			e.Performers = []Performer{}
			events = append(events, e)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(events)
	}
}

type Ticket struct {
	ID         string `json:"id"`
	Section    string `json:"section"`
	Row        string `json:"row"`
	Seat       string `json:"seat"`
	PriceCents int    `json:"price_cents"`
	Status     string `json:"status"`
}

func getEventTickets(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")

		rows, err := pool.Query(r.Context(), `
			SELECT id, section, row, seat, price_cents, status
			FROM tickets
			WHERE event_id = $1
			ORDER BY section, row, seat
		`, id)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		tickets := []Ticket{}
		for rows.Next() {
			var t Ticket
			if err := rows.Scan(&t.ID, &t.Section, &t.Row, &t.Seat, &t.PriceCents, &t.Status); err != nil {
				http.Error(w, "internal error", http.StatusInternalServerError)
				return
			}
			tickets = append(tickets, t)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(tickets)
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
