import { useState } from 'react'
import { Link, useNavigate } from 'react-router'
import { ArrowLeftIcon } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Field, FieldGroup, FieldLabel } from '@/components/ui/field'
import { useAuth, useChangePassword, useUpdateName } from '@/lib/auth'

export function ProfilePage() {
  const { user, signOut } = useAuth()
  const navigate = useNavigate()
  const updateName = useUpdateName()
  const changePassword = useChangePassword()

  const [name, setName] = useState(user?.name ?? '')
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [nameMsg, setNameMsg] = useState('')
  const [pwdMsg, setPwdMsg] = useState('')
  const [errorMsg, setErrorMsg] = useState('')

  const handleUpdateName = (e: React.FormEvent) => {
    e.preventDefault()
    if (!name.trim()) return
    updateName.mutate(name.trim(), {
      onSuccess: () => setNameMsg('Name updated successfully'),
      onError: (err) => setErrorMsg(err.message),
    })
  }

  const handleChangePassword = (e: React.FormEvent) => {
    e.preventDefault()
    if (!currentPassword || !newPassword) return
    changePassword.mutate(
      { currentPassword, newPassword },
      {
        onSuccess: () => {
          setPwdMsg('Password updated successfully')
          setCurrentPassword('')
          setNewPassword('')
        },
        onError: (err) => setErrorMsg(err.message),
      },
    )
  }

  return (
    <div className="mx-auto max-w-xl p-6">
      <div className="mb-6 flex items-center justify-between">
        <Link
          to="/home"
          className="inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeftIcon className="size-4" /> Back to meetings
        </Link>
        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            signOut()
            navigate('/login')
          }}
        >
          Sign out
        </Button>
      </div>

      <h1 className="mb-6 text-2xl font-bold tracking-tight">Account settings</h1>

      <div className="space-y-8">
        <section className="rounded-lg border bg-card p-6 shadow-xs">
          <h2 className="mb-4 text-lg font-semibold">Profile details</h2>
          <form onSubmit={handleUpdateName} className="space-y-4">
            <FieldGroup>
              <Field>
                <FieldLabel>Email</FieldLabel>
                <Input value={user?.email ?? ''} disabled />
              </Field>
              <Field>
                <FieldLabel>Name</FieldLabel>
                <Input value={name} onChange={(e) => setName(e.target.value)} />
              </Field>
            </FieldGroup>
            {nameMsg && <p className="text-sm text-green-600">{nameMsg}</p>}
            <Button type="submit" disabled={updateName.isPending}>
              {updateName.isPending ? 'Saving...' : 'Save name'}
            </Button>
          </form>
        </section>

        {user?.provider === 'password' && (
          <section className="rounded-lg border bg-card p-6 shadow-xs">
            <h2 className="mb-4 text-lg font-semibold">Change password</h2>
            <form onSubmit={handleChangePassword} className="space-y-4">
              <FieldGroup>
                <Field>
                  <FieldLabel>Current password</FieldLabel>
                  <Input
                    type="password"
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                  />
                </Field>
                <Field>
                  <FieldLabel>New password</FieldLabel>
                  <Input
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                  />
                </Field>
              </FieldGroup>
              {pwdMsg && <p className="text-sm text-green-600">{pwdMsg}</p>}
              {errorMsg && <p className="text-sm text-destructive">{errorMsg}</p>}
              <Button type="submit" disabled={changePassword.isPending}>
                {changePassword.isPending ? 'Updating...' : 'Update password'}
              </Button>
            </form>
          </section>
        )}
      </div>
    </div>
  )
}
