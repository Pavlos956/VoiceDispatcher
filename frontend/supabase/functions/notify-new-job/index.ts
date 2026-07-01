import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build a signed JWT for the FCM HTTP v1 API using the service account key. */
async function getFcmAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  const encode = (obj: object) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

  const unsignedToken = `${encode(header)}.${encode(payload)}`

  // Import the RSA private key
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '')
  const binaryKey = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken),
  )

  const signedJwt =
    unsignedToken + '.' +
    btoa(String.fromCharCode(...new Uint8Array(signature)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

  // Exchange JWT for an OAuth2 access token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signedJwt,
    }),
  })

  const tokenData = await tokenRes.json()
  return tokenData.access_token as string
}

/** Send one FCM notification to a single device token. */
async function sendNotification(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  title: string,
  body: string,
): Promise<void> {
  await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: { title, body },
          android: { priority: 'high' },
        },
      }),
    },
  )
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

interface JobRecord {
  id: number
  name?: string
  address?: string
  priority?: string
  summary?: string
}

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE'
  table: string
  record: JobRecord
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
serve(async (req: Request) => {
  try {
    const payload: WebhookPayload = await req.json()

    // Only act on new job insertions
    if (payload.type !== 'INSERT') {
      return new Response('ignored', { status: 200 })
    }

    const job = payload.record
    const title = `🚨 New Job: ${job.name ?? 'Unknown Client'}`
    const body  = job.summary ?? `Priority: ${job.priority ?? 'Standard'}`

    // Load the Firebase service account from the Supabase secret
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountJson) {
      return new Response('FIREBASE_SERVICE_ACCOUNT secret not set', { status: 500 })
    }
    const serviceAccount: ServiceAccount = JSON.parse(serviceAccountJson)

    // Get all registered device tokens from Supabase
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )
    const { data: tokens, error } = await supabaseClient
      .from('device_tokens')
      .select('token')

    if (error) throw error
    if (!tokens || tokens.length === 0) {
      return new Response('no tokens registered', { status: 200 })
    }

    // Get FCM access token once, reuse for all devices
    const accessToken = await getFcmAccessToken(serviceAccount)

    // Fan out — send to every registered device in parallel
    await Promise.allSettled(
      tokens.map((row: { token: string }) =>
        sendNotification(
          accessToken,
          serviceAccount.project_id,
          row.token,
          title,
          body,
        ),
      ),
    )

    return new Response(JSON.stringify({ sent: tokens.length }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error(err)
    return new Response(String(err), { status: 500 })
  }
})
