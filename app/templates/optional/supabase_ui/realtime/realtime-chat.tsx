import { useState, useEffect, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { RealtimeChannel } from '@supabase/supabase-js'

interface ChatMessage {
  id: string
  content: string
  user: {
    name: string
  }
  createdAt: string
}

interface RealtimeChatProps {
  roomName: string
  username: string
  onMessage?: (messages: ChatMessage[]) => void
  messages?: ChatMessage[]
}

export function RealtimeChat({ roomName, username, onMessage, messages: initialMessages = [] }: RealtimeChatProps) {
  const [messages, setMessages] = useState<ChatMessage[]>(initialMessages)
  const [inputValue, setInputValue] = useState('')
  const [isConnected, setIsConnected] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const channelRef = useRef<RealtimeChannel | null>(null)

  useEffect(() => {
    // Set up realtime subscription
    const channel = supabase.channel(`chat:${roomName}`)
      .on('broadcast', { event: 'message' }, ({ payload }) => {
        const newMessage: ChatMessage = {
          id: payload.id,
          content: payload.content,
          user: { name: payload.username },
          createdAt: payload.createdAt,
        }
        
        setMessages(prev => {
          const updated = [...prev, newMessage]
          onMessage?.(updated)
          return updated
        })
      })
      .on('presence', { event: 'sync' }, () => {
        setIsConnected(true)
      })
      .subscribe()

    channelRef.current = channel

    // Track presence
    channel.track({ username })

    return () => {
      channel.unsubscribe()
    }
  }, [roomName, username, onMessage])

  useEffect(() => {
    // Scroll to bottom when messages change
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const sendMessage = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!inputValue.trim() || !channelRef.current) return

    const message = {
      id: crypto.randomUUID(),
      content: inputValue,
      username,
      createdAt: new Date().toISOString(),
    }

    await channelRef.current.send({
      type: 'broadcast',
      event: 'message',
      payload: message,
    })

    setInputValue('')
  }

  return (
    <div className="flex flex-col h-full bg-white rounded-lg shadow-lg">
      {/* Header */}
      <div className="px-6 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-semibold text-gray-900">Chat Room: {roomName}</h3>
          <div className="flex items-center">
            <div className={`w-2 h-2 rounded-full mr-2 ${isConnected ? 'bg-green-500' : 'bg-gray-400'}`} />
            <span className="text-sm text-gray-600">
              {isConnected ? 'Connected' : 'Connecting...'}
            </span>
          </div>
        </div>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-6 space-y-4">
        {messages.length === 0 ? (
          <div className="text-center text-gray-500 py-8">
            No messages yet. Start the conversation!
          </div>
        ) : (
          messages.map((message) => (
            <div
              key={message.id}
              className={`flex ${message.user.name === username ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-xs lg:max-w-md px-4 py-2 rounded-lg ${
                  message.user.name === username
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-200 text-gray-900'
                }`}
              >
                <div className="text-xs opacity-75 mb-1">
                  {message.user.name}
                </div>
                <div className="text-sm">{message.content}</div>
                <div className="text-xs opacity-75 mt-1">
                  {new Date(message.createdAt).toLocaleTimeString()}
                </div>
              </div>
            </div>
          ))
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <form onSubmit={sendMessage} className="px-6 py-4 border-t border-gray-200">
        <div className="flex space-x-4">
          <input
            type="text"
            value={inputValue}
            onChange={(e) => setInputValue(e.target.value)}
            placeholder="Type a message..."
            className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            disabled={!isConnected}
          />
          <button
            type="submit"
            disabled={!isConnected || !inputValue.trim()}
            className="px-6 py-2 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Send
          </button>
        </div>
      </form>
    </div>
  )
}