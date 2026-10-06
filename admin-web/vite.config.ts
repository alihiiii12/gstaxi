import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  /** جذر Laravel (مجلد public) — يُستخدم فقط عند VITE_API_BASE_URL=/api */
  const laravelOrigin =
    env.VITE_LARAVEL_ORIGIN?.replace(/\/$/, '') ||
    'http://localhost/SyriaTaxi-main/public'

  return {
    base: '/admin/',
    plugins: [react()],
    server: {
      proxy: {
        '/api': {
          target: laravelOrigin,
          changeOrigin: true,
        },
      },
    },
  }
})
