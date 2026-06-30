package main

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type reserveRequest struct {
	TicketID string `json:"ticket_id"`
	UserID   string `json:"user_id"`
}

type reserveResponse struct {
	BookingID string `json:"booking_id"`
}

type confirmRequest struct {
	BookingID string `json:"booking_id"`
	UserID    string `json:"user_id"`
}

type confirmResponse struct {
	BookingID string `json:"booking_id"`
	Status    string `json:"status"`
}

// reserve claims a ticket for a user using a SELECT … FOR UPDATE inside a
// transaction. This serializes concurrent attempts at the DB level — no
// external lock (Redis, etc.) is needed. If another goroutine holds the row
// lock, this transaction blocks until that one commits or rolls back, then
// sees the updated status and correctly returns 409.
func reserve(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req reserveRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TicketID == "" || req.UserID == "" {
			http.Error(w, "ticket_id and user_id are required", http.StatusBadRequest)
			return
		}

		tx, err := pool.Begin(r.Context())
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer tx.Rollback(r.Context())

		var status string
		var expiresAt *time.Time
		err = tx.QueryRow(r.Context(),
			`SELECT status, expires_at FROM tickets WHERE id = $1 FOR UPDATE`,
			req.TicketID,
		).Scan(&status, &expiresAt)
		if err == pgx.ErrNoRows {
			http.Error(w, "ticket not found", http.StatusNotFound)
			return
		}
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		// Reject if already booked, or reserved and not yet expired.
		if status == "booked" {
			http.Error(w, "ticket already booked", http.StatusConflict)
			return
		}
		if status == "reserved" && expiresAt != nil && expiresAt.After(time.Now()) {
			http.Error(w, "ticket already reserved", http.StatusConflict)
			return
		}

		expiry := time.Now().Add(10 * time.Minute)
		_, err = tx.Exec(r.Context(),
			`UPDATE tickets SET status='reserved', reserved_by=$1, expires_at=$2 WHERE id=$3`,
			req.UserID, expiry, req.TicketID,
		)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		var bookingID string
		err = tx.QueryRow(r.Context(),
			`INSERT INTO bookings (ticket_id, user_id, status) VALUES ($1, $2, 'pending') RETURNING id`,
			req.TicketID, req.UserID,
		).Scan(&bookingID)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		if err := tx.Commit(r.Context()); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		writeJSON(w, http.StatusOK, reserveResponse{BookingID: bookingID})
	}
}

func confirm(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req confirmRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.BookingID == "" || req.UserID == "" {
			http.Error(w, "booking_id and user_id are required", http.StatusBadRequest)
			return
		}

		tx, err := pool.Begin(r.Context())
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		defer tx.Rollback(r.Context())

		var ticketID, bookingStatus string
		err = tx.QueryRow(r.Context(),
			`SELECT ticket_id, status FROM bookings WHERE id = $1 AND user_id = $2 FOR UPDATE`,
			req.BookingID, req.UserID,
		).Scan(&ticketID, &bookingStatus)
		if err == pgx.ErrNoRows {
			http.Error(w, "booking not found", http.StatusNotFound)
			return
		}
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		if bookingStatus != "pending" {
			http.Error(w, "booking is not in pending state", http.StatusConflict)
			return
		}

		if _, err := tx.Exec(r.Context(),
			`UPDATE tickets SET status='booked', expires_at=NULL WHERE id=$1`, ticketID,
		); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		if _, err := tx.Exec(r.Context(),
			`UPDATE bookings SET status='confirmed' WHERE id=$1`, req.BookingID,
		); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		if err := tx.Commit(r.Context()); err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		writeJSON(w, http.StatusOK, confirmResponse{BookingID: req.BookingID, Status: "confirmed"})
	}
}

// pay is a stub — payment gateway integration is explicitly out of scope.
func pay() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "payment_accepted"})
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
