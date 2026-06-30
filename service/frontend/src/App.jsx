import { useState, useEffect, useCallback } from 'react'
import * as api from './api'

// ── Session user ID ───────────────────────────────────────────────────────

function generateUUID() {
  // crypto.randomUUID() requires HTTPS; this fallback works over HTTP too
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16)
  })
}

function getOrCreateUserId() {
  const KEY = 'tm_user_id'
  let id = sessionStorage.getItem(KEY)
  if (!id) { id = generateUUID(); sessionStorage.setItem(KEY, id) }
  return id
}
const USER_ID = getOrCreateUserId()

// ── Formatters ────────────────────────────────────────────────────────────

function fmtDate(iso) {
  return new Date(iso).toLocaleString('en-IN', {
    weekday: 'short', day: 'numeric', month: 'short',
    year: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

function fmtPrice(cents) {
  return '₹' + (cents / 100).toLocaleString('en-IN')
}

// ── Spinner ───────────────────────────────────────────────────────────────

function Spinner({ dark = false }) {
  return <span className={`spinner${dark ? ' dark' : ''}`} role="status" aria-label="Loading" />
}

// ── SearchView ────────────────────────────────────────────────────────────

function SearchView({ onSelectEvent }) {
  const [query, setQuery]     = useState('')
  const [events, setEvents]   = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError]     = useState(null)
  const [didSearch, setDidSearch] = useState(false)

  const doSearch = useCallback(async (q) => {
    const trimmed = q.trim()
    if (!trimmed) return
    setLoading(true); setError(null)
    try {
      setEvents(await api.searchEvents(trimmed))
      setDidSearch(true)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [])

  // Load seed data on mount
  useEffect(() => { doSearch('bollywood rahman concert live') }, [doSearch])

  const handleKey = (e) => { if (e.key === 'Enter') doSearch(query) }

  const available = events.filter(
    ev => !ev.performers // search returns events without per-event performer counts
  ).length

  return (
    <div>
      <div className="search-hero">
        <h1>Find Your Next Experience</h1>
        <p>Search concerts, shows, and live events</p>
        <div className="search-bar">
          <input
            className="search-input"
            placeholder="e.g. bollywood, rahman, concert…"
            value={query}
            onChange={e => setQuery(e.target.value)}
            onKeyDown={handleKey}
            aria-label="Search events"
          />
          <button
            className="search-btn"
            onClick={() => doSearch(query)}
            disabled={loading}
          >
            {loading ? <Spinner /> : null}
            {loading ? 'Searching…' : 'Search'}
          </button>
        </div>
      </div>

      {error && (
        <div className="booking-error" style={{maxWidth:580, margin:'0 auto 24px'}}>
          <span>⚠️</span> {error}
        </div>
      )}

      {!loading && didSearch && events.length === 0 && (
        <div className="empty-state">
          <div className="empty-icon">🔍</div>
          <div className="empty-title">No events found</div>
          <div className="empty-sub">Try different keywords</div>
        </div>
      )}

      {events.length > 0 && (
        <>
          <p className="results-meta">
            {events.length} event{events.length !== 1 ? 's' : ''} found
          </p>
          <div className="events-grid">
            {events.map(ev => (
              <EventCard key={ev.id} event={ev} onClick={() => onSelectEvent(ev.id)} />
            ))}
          </div>
        </>
      )}
    </div>
  )
}

// ── EventCard ─────────────────────────────────────────────────────────────

function EventCard({ event, onClick }) {
  return (
    <article className="event-card" onClick={onClick} role="button" tabIndex={0}
      onKeyDown={e => e.key === 'Enter' && onClick()}>
      <div className="event-card-header">
        <div className="event-card-title">{event.title}</div>
        <div className="event-card-date">🗓 {fmtDate(event.starts_at)}</div>
      </div>
      <div className="event-card-body">
        <div className="event-card-venue">
          <span>📍</span>
          <span>{event.venue.name}, {event.venue.city}</span>
        </div>
        {event.performers && event.performers.length > 0 && (
          <div className="event-card-performers">
            {event.performers.map(p => (
              <span key={p.id} className="tag">{p.name}</span>
            ))}
          </div>
        )}
      </div>
    </article>
  )
}

// ── TicketsPanel ──────────────────────────────────────────────────────────

function TicketsPanel({ tickets, activeTicketId, onReserve }) {
  const available = tickets.filter(t => t.status === 'available').length

  return (
    <div className="tickets-panel">
      <div className="tickets-panel-header">
        <h2>Tickets</h2>
        <span className="tickets-count">{available} available</span>
      </div>

      {tickets.length === 0 ? (
        <div className="empty-state" style={{padding:'36px 20px'}}>
          <div className="empty-icon" style={{fontSize:'1.8rem'}}>🎟</div>
          <div className="empty-sub">No tickets found</div>
        </div>
      ) : (
        <div className="tickets-list">
          {tickets.map(t => {
            const isActive = t.id === activeTicketId
            const unavailable = t.status !== 'available'
            return (
              <div
                key={t.id}
                className={`ticket-row${isActive ? ' active-ticket' : ''}${unavailable ? ' unavailable' : ''}`}
              >
                <div className="ticket-info">
                  <div className="ticket-section">{t.section}</div>
                  <div className="ticket-seat">Row {t.row} · Seat {t.seat}</div>
                </div>
                <div className="ticket-price">{fmtPrice(t.price_cents)}</div>
                <span className={`status-pill status-${t.status}`}>{t.status}</span>
                <button
                  className="reserve-btn"
                  disabled={unavailable || isActive}
                  onClick={() => onReserve(t.id)}
                >
                  {isActive ? 'Selected' : 'Reserve'}
                </button>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── BookingPanel ──────────────────────────────────────────────────────────
// booking shape: { ticketId, bookingId?, step, error? }
// step: 'reserving' | 'reserved' | 'confirming' | 'confirmed' | 'paying' | 'paid' | 'error'

const STEPS = [
  { id: 'reserve', label: 'Reserve'  },
  { id: 'confirm', label: 'Confirm'  },
  { id: 'pay',     label: 'Pay'      },
]

function stepPhase(step) {
  if (['reserving', 'reserved'].includes(step)) return 0
  if (['confirming', 'confirmed'].includes(step)) return 1
  if (['paying', 'paid'].includes(step)) return 2
  return -1
}

function BookingPanel({ booking, onUpdate, onClose, onTicketsRefresh }) {
  const { ticketId, bookingId, step, error } = booking
  const phase = stepPhase(step)
  const busy = ['reserving', 'confirming', 'paying'].includes(step)

  const doReserve = useCallback(async () => {
    onUpdate(b => ({ ...b, step: 'reserving', error: null }))
    try {
      const res = await api.reserveTicket(ticketId, USER_ID)
      onUpdate(b => ({ ...b, bookingId: res.booking_id, step: 'reserved', error: null }))
      onTicketsRefresh()
    } catch (e) {
      onUpdate(b => ({ ...b, step: 'error', error: e.message }))
    }
  }, [ticketId, onUpdate, onTicketsRefresh])

  const doConfirm = useCallback(async () => {
    onUpdate(b => ({ ...b, step: 'confirming', error: null }))
    try {
      await api.confirmBooking(bookingId, USER_ID)
      onUpdate(b => ({ ...b, step: 'confirmed', error: null }))
      onTicketsRefresh()
    } catch (e) {
      onUpdate(b => ({ ...b, step: 'error', error: e.message }))
    }
  }, [bookingId, onUpdate, onTicketsRefresh])

  const doPay = useCallback(async () => {
    onUpdate(b => ({ ...b, step: 'paying', error: null }))
    try {
      await api.payBooking()
      onUpdate(b => ({ ...b, step: 'paid', error: null }))
    } catch (e) {
      onUpdate(b => ({ ...b, step: 'error', error: e.message }))
    }
  }, [onUpdate])

  // Auto-trigger reserve on mount
  useEffect(() => {
    if (step === 'idle') doReserve()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="booking-panel">
      <div className="booking-panel-header">
        <h3>Booking Flow</h3>
        <button className="close-btn" onClick={onClose} aria-label="Close">✕</button>
      </div>

      {/* Step indicator */}
      <div className="steps">
        {STEPS.map((s, i) => {
          const cls = phase > i ? 'done' : phase === i ? 'active' : ''
          return <div key={s.id} className={`step ${cls}`}>{phase > i ? '✓ ' : ''}{s.label}</div>
        })}
      </div>

      <div className="booking-body">
        {/* IDs */}
        <div className="info-row">
          <div className="info-row-label">Your Session User ID</div>
          <code>{USER_ID}</code>
        </div>
        <div className="info-row">
          <div className="info-row-label">Ticket ID</div>
          <code>{ticketId}</code>
        </div>
        {bookingId && (
          <div className="info-row highlight">
            <div className="info-row-label">Booking ID</div>
            <code>{bookingId}</code>
          </div>
        )}

        {/* Paid success */}
        {step === 'paid' && (
          <div className="success-banner">
            <div className="success-icon">🎉</div>
            <div className="success-title">Payment accepted!</div>
            <div className="success-sub">Your booking is confirmed. Enjoy the show!</div>
          </div>
        )}

        {/* Error */}
        {step === 'error' && (
          <div className="booking-error">
            <span>⚠️</span>
            <div>
              <strong>Error:</strong> {error}
              <br />
              <button
                style={{
                  marginTop: 8, background: 'none', border: 'none',
                  color: 'var(--red)', cursor: 'pointer', padding: 0,
                  fontWeight: 700, fontSize: '0.83rem', textDecoration: 'underline',
                }}
                onClick={doReserve}
              >Retry reserve</button>
            </div>
          </div>
        )}

        {/* CTA buttons */}
        {step === 'reserving' && (
          <button className="action-btn" disabled>
            <Spinner /> Reserving ticket…
          </button>
        )}
        {step === 'reserved' && (
          <button className="action-btn" onClick={doConfirm}>
            Confirm Booking →
          </button>
        )}
        {step === 'confirming' && (
          <button className="action-btn" disabled>
            <Spinner /> Confirming…
          </button>
        )}
        {step === 'confirmed' && (
          <button className="action-btn" onClick={doPay}>
            Pay Now →
          </button>
        )}
        {step === 'paying' && (
          <button className="action-btn" disabled>
            <Spinner /> Processing payment…
          </button>
        )}
        {step === 'paid' && (
          <button className="action-btn done">
            ✓ Payment complete
          </button>
        )}
      </div>
    </div>
  )
}

// ── EventView ─────────────────────────────────────────────────────────────

function EventView({ eventId }) {
  const [event,   setEvent]   = useState(null)
  const [tickets, setTickets] = useState([])
  const [loading, setLoading] = useState(true)
  const [booking, setBooking] = useState(null)

  const refreshTickets = useCallback(async () => {
    try {
      setTickets(await api.getEventTickets(eventId))
    } catch (_) { /* silent */ }
  }, [eventId])

  useEffect(() => {
    setLoading(true)
    Promise.all([api.getEvent(eventId), api.getEventTickets(eventId)])
      .then(([ev, tix]) => { setEvent(ev); setTickets(tix) })
      .catch(console.error)
      .finally(() => setLoading(false))
  }, [eventId])

  if (loading) return (
    <div className="page-loader"><Spinner dark /></div>
  )
  if (!event) return (
    <div className="empty-state">
      <div className="empty-icon">❌</div>
      <div className="empty-title">Event not found</div>
    </div>
  )

  const handleReserve = (ticketId) => {
    setBooking({ ticketId, step: 'idle', bookingId: null, error: null })
  }

  return (
    <div className="event-detail">
      {/* Left column: event info */}
      <div>
        <div className="event-info">
          <div className="event-info-header">
            <h1>{event.title}</h1>
            <div className="event-date-line">
              <span>🗓</span> {fmtDate(event.starts_at)}
            </div>
          </div>
          <div className="event-info-body">
            {event.description && (
              <>
                <p className="section-label">About</p>
                <p className="description">{event.description}</p>
              </>
            )}

            <p className="section-label">Venue</p>
            <div className="venue-block">
              <div className="venue-name">{event.venue.name}</div>
              <div className="venue-meta">
                📍 {event.venue.city}, {event.venue.country}
                &nbsp;·&nbsp; Capacity: {event.venue.capacity.toLocaleString()}
              </div>
            </div>

            {event.performers.length > 0 && (
              <>
                <p className="section-label">Performers</p>
                <div className="performers-row">
                  {event.performers.map(p => (
                    <span key={p.id} className="tag tag-lg">🎤 {p.name}</span>
                  ))}
                </div>
              </>
            )}

            <p className="section-label">Event ID</p>
            <div className="id-block"><code>{event.id}</code></div>
          </div>
        </div>
      </div>

      {/* Right column: tickets + booking panel */}
      <div>
        <TicketsPanel
          tickets={tickets}
          activeTicketId={booking?.ticketId}
          onReserve={handleReserve}
        />
        {booking && (
          <BookingPanel
            booking={booking}
            onUpdate={setBooking}
            onClose={() => { setBooking(null); refreshTickets() }}
            onTicketsRefresh={refreshTickets}
          />
        )}
      </div>
    </div>
  )
}

// ── App (root) ────────────────────────────────────────────────────────────

export default function App() {
  const [view, setView]         = useState('search') // 'search' | 'event'
  const [eventId, setEventId]   = useState(null)

  const openEvent = (id) => { setEventId(id); setView('event') }
  const goBack    = ()   => { setView('search'); setEventId(null) }

  return (
    <div className="app">
      <header className="header">
        <div className="header-inner">
          <div className="logo">🎫 <span>TicketMaster</span></div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            {view === 'event' && (
              <button className="back-btn" onClick={goBack}>
                ← Back to Search
              </button>
            )}
            <div className="user-badge">
              <strong>Session user:</strong>
              <code title={USER_ID}>{USER_ID.slice(0, 8)}…</code>
            </div>
          </div>
        </div>
      </header>

      <main className="main">
        {view === 'search' && <SearchView onSelectEvent={openEvent} />}
        {view === 'event'  && <EventView eventId={eventId} />}
      </main>
    </div>
  )
}
