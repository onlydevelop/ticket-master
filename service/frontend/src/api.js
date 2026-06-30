const EVENTS   = '/api/events'
const BOOKINGS = '/api/bookings'

async function call(url, opts = {}) {
  const res = await fetch(url, opts)
  const text = await res.text()
  if (!res.ok) throw new Error(text.trim() || `HTTP ${res.status}`)
  return text ? JSON.parse(text) : null
}

export const searchEvents    = (q)              => call(`${EVENTS}/search?q=${encodeURIComponent(q)}`)
export const getEvent        = (id)             => call(`${EVENTS}/${id}`)
export const getEventTickets = (id)             => call(`${EVENTS}/${id}/tickets`)
export const reserveTicket   = (ticketId, uid)  => call(`${BOOKINGS}/reserve`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ ticket_id: ticketId, user_id: uid }),
})
export const confirmBooking  = (bookingId, uid) => call(`${BOOKINGS}/confirm`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ booking_id: bookingId, user_id: uid }),
})
export const payBooking      = ()               => call(`${BOOKINGS}/pay`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: '{}',
})
