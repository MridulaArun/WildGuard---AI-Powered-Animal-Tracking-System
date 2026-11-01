import 'dotenv/config'
import express from 'express'
import cors from 'cors'
import pg from 'pg'

const { Pool } = pg
const app = express()
app.use(cors())
app.use(express.json())
const port = process.env.PORT || 4000
const pool = process.env.DATABASE_URL ? new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
  max: 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 7000
}) : null

const safeQuery = async (sql, params = []) => {
  if (!pool) throw new Error('DATABASE_URL is not configured')
  const { rows } = await pool.query(sql, params)
  return rows
}
app.get('/api/health', async (_req, res) => {
  if (!pool) return res.status(503).json({ ok: false, mode: 'demo', message: 'DATABASE_URL not configured' })
  try { await pool.query('SELECT 1'); res.json({ ok: true, mode: 'database' }) }
  catch (e) { res.status(503).json({ ok: false, mode: 'demo', message: e.message }) }
})
app.get('/api/overview', async (_req, res) => {
  try {
    const [animals, alerts, predictions, devices, reserves, workload, trend] = await Promise.all([
      safeQuery(`SELECT count(*)::int AS total, count(*) FILTER (WHERE status='active')::int AS active FROM Animal`),
      safeQuery(`SELECT count(*) FILTER (WHERE status IN ('open','acknowledged'))::int AS open, count(*) FILTER (WHERE severity='critical' AND status IN ('open','acknowledged'))::int AS critical FROM Alert`),
      safeQuery(`SELECT count(*) FILTER (WHERE review_status='unreviewed')::int AS review_queue, round(avg(risk_probability)*100)::int AS avg_probability FROM Prediction`),
      safeQuery(`SELECT count(*) FILTER (WHERE status='active')::int AS active, count(*) FILTER (WHERE battery_level < 25)::int AS low_battery FROM Device`),
      safeQuery(`SELECT count(*)::int AS total FROM Reserve`),
      safeQuery(`SELECT * FROM v_ranger_workload ORDER BY 1 LIMIT 6`),
      safeQuery(`SELECT date_trunc('day', created_at)::date AS day, count(*)::int AS alerts FROM Alert WHERE created_at >= now()-interval '7 days' GROUP BY 1 ORDER BY 1`)
    ])
    res.json({ animals: animals[0], alerts: alerts[0], predictions: predictions[0], devices: devices[0], reserves: reserves[0], workload, trend })
  } catch (e) { res.status(500).json({ error: e.message }) }
})
app.get('/api/animals', async (_req, res) => {
  try {
    res.json(await safeQuery(`SELECT a.animal_id, a.tag_id, a.sex, a.birth_year, a.status, s.species_name, s.scientific_name, s.conservation_status, r.reserve_name, p.last_seen, p.latitude, p.longitude, p.inside_home_reserve, d.model AS device_model, d.battery_level, h.health_status, h.checkup_date
      FROM Animal a JOIN Species s USING(species_id) LEFT JOIN Reserve r ON r.reserve_id=a.home_reserve_id
      LEFT JOIN LATERAL (SELECT timestamp AS last_seen, ST_Y(location) AS latitude, ST_X(location) AS longitude, ST_Within(location, r.boundary) AS inside_home_reserve FROM GPS_Tracking WHERE animal_id=a.animal_id ORDER BY timestamp DESC LIMIT 1) p ON true
      LEFT JOIN LATERAL (SELECT model,battery_level FROM Device WHERE animal_id=a.animal_id ORDER BY device_id DESC LIMIT 1) d ON true
      LEFT JOIN LATERAL (SELECT health_status,checkup_date FROM Health_Record WHERE animal_id=a.animal_id ORDER BY checkup_date DESC LIMIT 1) h ON true ORDER BY a.animal_id`))
  } catch (e) { res.status(500).json({ error: e.message }) }
})
app.get('/api/alerts', async (_req, res) => {
  try { res.json(await safeQuery(`SELECT * FROM v_open_alerts ORDER BY created_at DESC LIMIT 100`)) }
  catch (e) { res.status(500).json({ error: e.message }) }
})
app.get('/api/predictions', async (_req, res) => {
  try { res.json(await safeQuery(`SELECT * FROM v_prediction_review_queue ORDER BY predicted_at DESC LIMIT 100`)) }
  catch (e) { res.status(500).json({ error: e.message }) }
})
app.get('/api/reserves', async (_req, res) => {
  try { res.json(await safeQuery(`SELECT * FROM v_reserve_risk_summary ORDER BY 1`)) }
  catch (e) { res.status(500).json({ error: e.message }) }
})
app.get('/api/rangers', async (_req, res) => {
  try { res.json(await safeQuery(`SELECT * FROM v_ranger_workload ORDER BY 1`)) }
  catch (e) { res.status(500).json({ error: e.message }) }
})
app.get('/api/devices', async (_req, res) => {
  try { res.json(await safeQuery(`SELECT * FROM v_device_health ORDER BY 1`)) }
  catch (e) { res.status(500).json({ error: e.message }) }
})
app.patch('/api/alerts/:id', async (req, res) => {
  const id = Number(req.params.id)
  const { status } = req.body
  if (!Number.isInteger(id) || !['open','acknowledged','resolved','dismissed'].includes(status))
    return res.status(400).json({ error: 'Invalid alert id or status' })
  const client = await pool?.connect().catch(() => null)
  if (!client) return res.status(503).json({ error: 'Database connection unavailable' })
  try {
    await client.query('BEGIN')
    await client.query('UPDATE Alert SET status=$1 WHERE alert_id=$2', [status, id])
    if (status === 'resolved') await client.query(`UPDATE Alert_Assignment SET response_status='resolved' WHERE alert_id=$1 AND response_status <> 'resolved'`, [id])
    if (status === 'acknowledged') await client.query(`UPDATE Alert_Assignment SET response_status='in_progress' WHERE alert_id=$1 AND response_status='pending'`, [id])
    await client.query('COMMIT')
    res.json({ ok: true, alert_id: id, status })
  } catch (e) { await client.query('ROLLBACK'); res.status(500).json({ error: e.message }) }
  finally { client.release() }
})
app.listen(port, () => console.log(`WildGuard API listening on http://localhost:${port}`))
