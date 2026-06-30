import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const EVENT_SERVICE   = process.env.EVENT_SERVICE_URL   || 'http://localhost:8080'
const BOOKING_SERVICE = process.env.BOOKING_SERVICE_URL || 'http://localhost:8081'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    proxy: {
      '/api/events': {
        target: EVENT_SERVICE,
        changeOrigin: true,
        rewrite: path => path.replace(/^\/api\/events/, '/events'),
      },
      '/api/bookings': {
        target: BOOKING_SERVICE,
        changeOrigin: true,
        rewrite: path => path.replace(/^\/api\/bookings/, '/bookings'),
      },
    },
  },
})
