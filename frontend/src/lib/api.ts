import { signOut } from 'aws-amplify/auth'

import { getIdToken } from '@/lib/auth'

export type Participant = {
  id: string
  name: string
  email: string
}

export type Meeting = {
  id: string
  title: string
  description: string
  starts_at: string
  ends_at: string
  place: string
  participants: Participant[]
  created_at: string
}

export type MeetingCreate = {
  title: string
  description: string
  starts_at: string
  ends_at: string
  place: string
  participant_ids: string[]
}

export type ParticipantCreate = {
  name: string
  email: string
}

export type AgendaItem = {
  topic: string
  owner?: string | null
  minutes?: number | null
}

export type ActionItem = {
  task: string
  owner?: string | null
  due?: string | null
}

export type ParsedAgenda = {
  title?: string | null
  starts_at?: string | null
  duration_minutes?: number | null
  items: AgendaItem[]
  action_items: ActionItem[]
  language?: string
}

export type ParseAgendaResponse = {
  agenda: ParsedAgenda
  metadata: {
    model: string
    prompt_version: string
    input_tokens: number
    output_tokens: number
    latency_ms: number
    cost_usd: number
  }
}

export type Agenda = {
  id: string
  meeting_id: string
  items: AgendaItem[]
  action_items: ActionItem[]
  ai_suggestion?: Record<string, unknown> | null
  created_at: string
  updated_at: string
}

export type AgendaCreate = {
  items: AgendaItem[]
  action_items: ActionItem[]
  ai_suggestion?: Record<string, unknown> | null
}

export class ApiError extends Error {
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

// Backend origin, set at build time for AWS (the Lambda function URL). Empty locally,
// where the Vite dev server or nginx proxies /api to the backend.
const rawUrl = (import.meta.env.VITE_API_URL ?? '').trim().replace(/\/+$/, '')
const API_URL = rawUrl.endsWith('/api') ? rawUrl.slice(0, -4) : rawUrl

type ValidationIssue = { loc?: (string | number)[]; msg: string }

function errorMessage(detail: unknown, fallback: string): string {
  if (typeof detail === 'string') return detail
  if (Array.isArray(detail)) {
    return (detail as ValidationIssue[])
      .map((issue) => {
        const field = issue.loc?.filter((part) => part !== 'body').join('.')
        const msg = issue.msg.replace(/^Value error, /, '')
        return field ? `${field}: ${msg}` : msg
      })
      .join('; ')
  }
  return fallback
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = await getIdToken()
  const response = await fetch(`${API_URL}/api${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token && { Authorization: `Bearer ${token}` }),
      ...init?.headers,
    },
  })

  // The session is gone (revoked, or the refresh token expired): sign out, which sends the
  // user back to the login page (see AuthProvider).
  if (response.status === 401) await signOut().catch(() => undefined)

  if (!response.ok) {
    let detail: unknown
    try {
      detail = (await response.json()).detail
    } catch {
      // body was not JSON
    }
    throw new ApiError(response.status, errorMessage(detail, response.statusText))
  }

  if (response.status === 204) return undefined as T
  return response.json() as Promise<T>
}

export const api = {
  listMeetings: () => request<Meeting[]>('/meetings'),
  createMeeting: (data: MeetingCreate) =>
    request<Meeting>('/meetings', { method: 'POST', body: JSON.stringify(data) }),
  updateMeeting: ({ id, ...data }: MeetingCreate & { id: string }) =>
    request<Meeting>(`/meetings/${id}`, { method: 'PUT', body: JSON.stringify(data) }),
  deleteMeeting: (id: string) => request<void>(`/meetings/${id}`, { method: 'DELETE' }),
  listParticipants: () => request<Participant[]>('/participants'),
  createParticipant: (data: ParticipantCreate) =>
    request<Participant>('/participants', { method: 'POST', body: JSON.stringify(data) }),
  getAgenda: (meetingId: string) => request<Agenda>(`/meetings/${meetingId}/agenda`),
  saveAgenda: (meetingId: string, data: AgendaCreate) =>
    request<Agenda>(`/meetings/${meetingId}/agenda`, {
      method: 'POST',
      body: JSON.stringify(data),
    }),
  parseAgenda: async (
    text: string,
    today?: string,
    tz?: string,
    signal?: AbortSignal,
  ): Promise<ParseAgendaResponse> => {
    const token = await getIdToken()
    const parserUrl = (import.meta.env.VITE_AGENDA_PARSER_URL ?? '').trim().replace(/\/+$/, '')
    const targetUrl = parserUrl || `${API_URL}/api/agenda/parse`

    const response = await fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token && { Authorization: `Bearer ${token}` }),
      },
      body: JSON.stringify({
        text,
        today: today || new Date().toISOString().split('T')[0],
        tz: tz || Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
      }),
      signal,
    })

    if (response.status === 401) await signOut().catch(() => undefined)

    if (!response.ok) {
      let detail: unknown
      try {
        detail = (await response.json()).detail
      } catch {
        // non-JSON response body
      }
      if (response.status === 413) {
        throw new ApiError(413, 'Agenda text is too long (maximum 10,000 characters allowed).')
      }
      if (response.status === 429) {
        throw new ApiError(
          429,
          'AI service is currently busy (rate limit exceeded). Please try again shortly.',
        )
      }
      throw new ApiError(response.status, errorMessage(detail, response.statusText))
    }

    return response.json() as Promise<ParseAgendaResponse>
  },
}
