import { useRef, useState } from 'react'
import {
  CalendarIcon,
  CheckCircle2Icon,
  ClockIcon,
  ListOrderedIcon,
  Loader2Icon,
  PencilIcon,
  PlusIcon,
  SparklesIcon,
  Trash2Icon,
  UserIcon,
  XIcon,
} from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { useMeetingAgenda, useSaveMeetingAgenda } from '@/hooks/queries'
import { api, type ActionItem, type AgendaItem, type Meeting } from '@/lib/api'

type ItemWithSuggestion = AgendaItem & { isSuggested?: boolean }
type ActionWithSuggestion = ActionItem & { isSuggested?: boolean }

type Props = {
  meeting: Meeting
}

export function AgendaSection({ meeting }: Props) {
  const { data: agenda, isLoading: isAgendaLoading } = useMeetingAgenda(meeting.id)
  const saveAgendaMutation = useSaveMeetingAgenda(meeting.id)

  const [isEditing, setIsEditing] = useState(false)
  const [pastedText, setPastedText] = useState('')
  const [isParsing, setIsParsing] = useState(false)
  const [parseError, setParseError] = useState<string | null>(null)
  const [items, setItems] = useState<ItemWithSuggestion[]>([])
  const [actionItems, setActionItems] = useState<ActionWithSuggestion[]>([])
  const [aiSuggestion, setAiSuggestion] = useState<Record<string, unknown> | null>(null)

  const abortControllerRef = useRef<AbortController | null>(null)

  const openEditor = () => {
    setIsEditing(true)
    setParseError(null)
    if (agenda) {
      setItems(agenda.items.map((i) => ({ ...i, isSuggested: false })))
      setActionItems(agenda.action_items.map((a) => ({ ...a, isSuggested: false })))
      setAiSuggestion(agenda.ai_suggestion ?? null)
    } else {
      setItems([])
      setActionItems([])
      setAiSuggestion(null)
    }
  }

  const handleCancelParsing = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort()
      abortControllerRef.current = null
    }
    setIsParsing(false)
    toast.info('Agenda parsing canceled.')
  }

  const handleParse = async () => {
    if (!pastedText.trim()) {
      toast.error('Please paste agenda text first.')
      return
    }

    if (pastedText.length > 10000) {
      toast.error('Agenda text exceeds 10,000 characters limit.')
      return
    }

    setIsParsing(true)
    setParseError(null)
    abortControllerRef.current = new AbortController()

    try {
      const result = await api.parseAgenda(
        pastedText,
        undefined,
        undefined,
        abortControllerRef.current.signal,
      )

      setItems(result.agenda.items.map((it) => ({ ...it, isSuggested: true })))
      setActionItems(result.agenda.action_items.map((ac) => ({ ...ac, isSuggested: true })))
      setAiSuggestion(result.agenda as unknown as Record<string, unknown>)
      toast.success('Agenda parsed successfully!')
    } catch (err: unknown) {
      if (err instanceof Error && err.name === 'AbortError') {
        // Handled in cancel
        return
      }
      const msg = err instanceof Error ? err.message : 'Failed to parse agenda'
      setParseError(msg)
      toast.error(msg)
    } finally {
      setIsParsing(false)
      abortControllerRef.current = null
    }
  }

  const handleItemChange = (
    index: number,
    field: keyof AgendaItem,
    value: string | number | null,
  ) => {
    setItems((prev) =>
      prev.map((item, idx) => {
        if (idx !== index) return item
        return {
          ...item,
          [field]: value,
          isSuggested: false, // Dismiss "suggested" badge on modification
        }
      }),
    )
  }

  const handleAddItem = () => {
    setItems((prev) => [...prev, { topic: '', owner: '', minutes: null, isSuggested: false }])
  }

  const handleDeleteItem = (index: number) => {
    setItems((prev) => prev.filter((_, idx) => idx !== index))
  }

  const handleActionItemChange = (index: number, field: keyof ActionItem, value: string | null) => {
    setActionItems((prev) =>
      prev.map((action, idx) => {
        if (idx !== index) return action
        return {
          ...action,
          [field]: value,
          isSuggested: false, // Dismiss "suggested" badge on modification
        }
      }),
    )
  }

  const handleAddActionItem = () => {
    setActionItems((prev) => [...prev, { task: '', owner: '', due: null, isSuggested: false }])
  }

  const handleDeleteActionItem = (index: number) => {
    setActionItems((prev) => prev.filter((_, idx) => idx !== index))
  }

  const handleSaveAgenda = async () => {
    const validItems = items
      .map((item) => ({
        topic: item.topic,
        owner: item.owner,
        minutes: item.minutes,
      }))
      .filter((i) => i.topic.trim().length > 0)
    const validActions = actionItems
      .map((action) => ({
        task: action.task,
        owner: action.owner,
        due: action.due,
      }))
      .filter((a) => a.task.trim().length > 0)

    try {
      await saveAgendaMutation.mutateAsync({
        items: validItems,
        action_items: validActions,
        ai_suggestion: aiSuggestion,
      })
      toast.success('Agenda saved!')
      setIsEditing(false)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to save agenda'
      toast.error(msg)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h3 className="flex items-center gap-2 text-lg">
          <ListOrderedIcon className="size-4" />
          Agenda & Action Items
          {agenda?.ai_suggestion && (
            <Badge variant="outline" className="text-xs font-normal">
              <SparklesIcon className="mr-1 size-3 text-amber-500" />
              AI Assisted
            </Badge>
          )}
        </h3>

        {!isEditing && (
          <Button
            variant="outline"
            size="sm"
            onClick={openEditor}
            className="flex items-center gap-1.5"
          >
            {agenda && (agenda.items.length > 0 || agenda.action_items.length > 0) ? (
              <>
                <PencilIcon className="size-3.5" />
                Edit Agenda
              </>
            ) : (
              <>
                <SparklesIcon className="size-3.5 text-amber-500" />
                Paste an agenda
              </>
            )}
          </Button>
        )}
      </div>

      {/* VIEW MODE */}
      {!isEditing && (
        <div className="flex flex-col gap-4">
          {isAgendaLoading ? (
            <div className="flex items-center gap-2 py-2 text-sm text-muted-foreground">
              <Loader2Icon className="size-4 animate-spin" />
              Loading agenda...
            </div>
          ) : !agenda || (agenda.items.length === 0 && agenda.action_items.length === 0) ? (
            <p className="text-sm text-muted-foreground">No agenda items added yet.</p>
          ) : (
            <>
              {agenda.items.length > 0 && (
                <div className="flex flex-col gap-2">
                  <h4 className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                    Discussion Topics
                  </h4>
                  <ul className="flex flex-col gap-1.5">
                    {agenda.items.map((item, idx) => (
                      <li
                        key={idx}
                        className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-muted/40 px-3 py-1.5 text-sm"
                      >
                        <div className="flex items-center gap-2 font-medium">
                          <span className="text-xs text-muted-foreground">{idx + 1}.</span>
                          <span>{item.topic}</span>
                        </div>
                        <div className="flex items-center gap-3 text-xs text-muted-foreground">
                          {item.owner && (
                            <span className="flex items-center gap-1">
                              <UserIcon className="size-3" />
                              {item.owner}
                            </span>
                          )}
                          {item.minutes && (
                            <span className="flex items-center gap-1">
                              <ClockIcon className="size-3" />
                              {item.minutes}m
                            </span>
                          )}
                        </div>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {agenda.action_items.length > 0 && (
                <div className="flex flex-col gap-2">
                  <h4 className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                    Action Items
                  </h4>
                  <ul className="flex flex-col gap-1.5">
                    {agenda.action_items.map((action, idx) => (
                      <li
                        key={idx}
                        className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-muted/40 px-3 py-1.5 text-sm"
                      >
                        <div className="flex items-center gap-2">
                          <CheckCircle2Icon className="size-3.5 text-primary" />
                          <span>{action.task}</span>
                        </div>
                        <div className="flex items-center gap-3 text-xs text-muted-foreground">
                          {action.owner && (
                            <span className="flex items-center gap-1">
                              <UserIcon className="size-3" />
                              {action.owner}
                            </span>
                          )}
                          {action.due && (
                            <span className="flex items-center gap-1">
                              <CalendarIcon className="size-3" />
                              {action.due}
                            </span>
                          )}
                        </div>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </>
          )}
        </div>
      )}

      {/* EDIT / PARSE MODE */}
      {isEditing && (
        <div className="flex flex-col gap-4 rounded-lg border border-border bg-card/60 p-4">
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <label className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                Paste Raw Agenda Text
              </label>
              <span
                className={`text-xs ${
                  pastedText.length > 10000 ? 'font-bold text-destructive' : 'text-muted-foreground'
                }`}
              >
                {pastedText.length} / 10,000
              </span>
            </div>
            <Textarea
              placeholder="Paste unstructured notes, email, or agenda in Ukrainian or English...&#10;e.g.&#10;Sprint planning:&#10;1. Retrospective (Andrii, 15m)&#10;2. Q4 Roadmap (Team, 30m)&#10;Action: finish CI deployment by Friday (Andrii)"
              rows={4}
              value={pastedText}
              onChange={(e) => setPastedText(e.target.value)}
              disabled={isParsing}
              className="resize-y text-sm"
            />
            {parseError && <p className="text-xs text-destructive">{parseError}</p>}
            <div className="flex items-center gap-2 pt-1">
              {isParsing ? (
                <>
                  <Button size="sm" disabled className="flex items-center gap-2">
                    <Loader2Icon className="size-3.5 animate-spin" />
                    Parsing with Bedrock...
                  </Button>
                  <Button size="sm" variant="outline" onClick={handleCancelParsing}>
                    Cancel
                  </Button>
                </>
              ) : (
                <Button
                  size="sm"
                  onClick={handleParse}
                  disabled={!pastedText.trim() || pastedText.length > 10000}
                  className="flex items-center gap-1.5"
                >
                  <SparklesIcon className="size-3.5" />
                  Parse Agenda
                </Button>
              )}
            </div>
          </div>

          <div className="hairline" />

          {/* EDITABLE TOPICS */}
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                Agenda Topics
              </span>
              <Button variant="ghost" size="sm" onClick={handleAddItem} className="h-7 text-xs">
                <PlusIcon className="mr-1 size-3" />
                Add Topic
              </Button>
            </div>

            {items.length === 0 ? (
              <p className="text-xs text-muted-foreground italic">No topics yet.</p>
            ) : (
              items.map((item, idx) => (
                <div
                  key={idx}
                  className="flex flex-col gap-2 rounded-md border border-border/80 bg-background/50 p-2 text-sm"
                >
                  <div className="flex items-center gap-2">
                    <Input
                      placeholder="Topic title (required)"
                      value={item.topic}
                      onChange={(e) => handleItemChange(idx, 'topic', e.target.value)}
                      className="h-8 text-sm flex-1"
                    />
                    {item.isSuggested && (
                      <Badge variant="secondary" className="shrink-0 text-[10px]">
                        <SparklesIcon className="mr-1 size-2.5 text-amber-500" />
                        suggested
                      </Badge>
                    )}
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleDeleteItem(idx)}
                      className="h-8 w-8 text-muted-foreground hover:text-destructive"
                    >
                      <Trash2Icon className="size-3.5" />
                    </Button>
                  </div>
                  <div className="flex items-center gap-2">
                    <Input
                      placeholder="Owner (optional)"
                      value={item.owner ?? ''}
                      onChange={(e) => handleItemChange(idx, 'owner', e.target.value)}
                      className="h-7 text-xs flex-1"
                    />
                    <Input
                      type="number"
                      placeholder="Minutes"
                      value={item.minutes ?? ''}
                      onChange={(e) =>
                        handleItemChange(
                          idx,
                          'minutes',
                          e.target.value ? parseInt(e.target.value, 10) : null,
                        )
                      }
                      className="h-7 w-24 text-xs"
                      min={1}
                      max={480}
                    />
                  </div>
                </div>
              ))
            )}
          </div>

          {/* EDITABLE ACTIONS */}
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">
                Action Items
              </span>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleAddActionItem}
                className="h-7 text-xs"
              >
                <PlusIcon className="mr-1 size-3" />
                Add Action
              </Button>
            </div>

            {actionItems.length === 0 ? (
              <p className="text-xs text-muted-foreground italic">No action items yet.</p>
            ) : (
              actionItems.map((action, idx) => (
                <div
                  key={idx}
                  className="flex flex-col gap-2 rounded-md border border-border/80 bg-background/50 p-2 text-sm"
                >
                  <div className="flex items-center gap-2">
                    <Input
                      placeholder="Task deliverable (required)"
                      value={action.task}
                      onChange={(e) => handleActionItemChange(idx, 'task', e.target.value)}
                      className="h-8 text-sm flex-1"
                    />
                    {action.isSuggested && (
                      <Badge variant="secondary" className="shrink-0 text-[10px]">
                        <SparklesIcon className="mr-1 size-2.5 text-amber-500" />
                        suggested
                      </Badge>
                    )}
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleDeleteActionItem(idx)}
                      className="h-8 w-8 text-muted-foreground hover:text-destructive"
                    >
                      <Trash2Icon className="size-3.5" />
                    </Button>
                  </div>
                  <div className="flex items-center gap-2">
                    <Input
                      placeholder="Assignee (optional)"
                      value={action.owner ?? ''}
                      onChange={(e) => handleActionItemChange(idx, 'owner', e.target.value)}
                      className="h-7 text-xs flex-1"
                    />
                    <Input
                      type="date"
                      placeholder="Due date"
                      value={action.due ?? ''}
                      onChange={(e) => handleActionItemChange(idx, 'due', e.target.value || null)}
                      className="h-7 w-36 text-xs"
                    />
                  </div>
                </div>
              ))
            )}
          </div>

          <div className="flex items-center justify-between pt-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setIsEditing(false)}
              disabled={saveAgendaMutation.isPending}
            >
              <XIcon className="mr-1 size-3.5" />
              Cancel
            </Button>
            <Button
              size="sm"
              onClick={handleSaveAgenda}
              disabled={saveAgendaMutation.isPending}
              className="flex items-center gap-1.5"
            >
              {saveAgendaMutation.isPending ? (
                <>
                  <Loader2Icon className="size-3.5 animate-spin" />
                  Saving...
                </>
              ) : (
                'Save Agenda'
              )}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
