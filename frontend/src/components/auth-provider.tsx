import { useQueryClient } from '@tanstack/react-query'
import { Hub } from 'aws-amplify/utils'
import { signOut as cognitoSignOut } from 'aws-amplify/auth'
import { useEffect, useState, type ReactNode } from 'react'

import { AuthContext, authConfig, authConfigured, loadUser, type User } from '@/lib/auth'

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient()
  const [user, setUser] = useState<User | null | undefined>(authConfigured ? undefined : null)

  useEffect(() => {
    if (!authConfigured) return
    let active = true
    const refresh = () => loadUser().then((next) => active && setUser(next))
    refresh()
    // Keeps the state in step with Cognito: the Google redirect, sign-out in another place
    // (e.g. a 401 from the API), or a refresh token that no longer works.
    const stop = Hub.listen('auth', ({ payload }) => {
      if (payload.event === 'signedIn' || payload.event === 'signInWithRedirect') refresh()
      if (payload.event === 'signedOut' || payload.event === 'tokenRefresh_failure') {
        setUser(null)
        // The next user must not see this user's cached meetings.
        queryClient.clear()
      }
    })
    return () => {
      active = false
      stop()
    }
  }, [queryClient])

  const signIn = (next: User) => setUser(next)
  const signOut = async () => {
    try {
      await cognitoSignOut()
    } catch {
      // ignore
    }
    setUser(null)
    queryClient.clear()
    if (authConfig.domain && authConfig.clientId) {
      const logoutRedirect = encodeURIComponent(`${window.location.origin}/login`)
      const domain = authConfig.domain.replace(/^https?:\/\//, '')
      window.location.assign(
        `https://${domain}/logout?client_id=${authConfig.clientId}&logout_uri=${logoutRedirect}`,
      )
    }
  }

  return <AuthContext value={{ user, signIn, signOut }}>{children}</AuthContext>
}
