import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import { api, type AgendaCreate } from '@/lib/api'

export const meetingsKey = ['meetings'] as const
export const participantsKey = ['participants'] as const
export const agendaKey = (meetingId: string) => ['meetings', meetingId, 'agenda'] as const

export function useMeetings() {
  return useQuery({ queryKey: meetingsKey, queryFn: api.listMeetings })
}

export function useParticipants() {
  return useQuery({ queryKey: participantsKey, queryFn: api.listParticipants })
}

export function useCreateMeeting() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.createMeeting,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: meetingsKey }),
  })
}

export function useUpdateMeeting() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.updateMeeting,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: meetingsKey }),
  })
}

export function useDeleteMeeting() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.deleteMeeting,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: meetingsKey }),
  })
}

export function useCreateParticipant() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.createParticipant,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: participantsKey }),
  })
}

export function useMeetingAgenda(meetingId: string | undefined) {
  return useQuery({
    queryKey: agendaKey(meetingId || ''),
    queryFn: () => (meetingId ? api.getAgenda(meetingId) : Promise.reject('No meeting ID')),
    enabled: Boolean(meetingId),
    retry: false,
  })
}

export function useSaveMeetingAgenda(meetingId: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: AgendaCreate) => api.saveAgenda(meetingId, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: agendaKey(meetingId) }),
  })
}
