<?php

namespace App\Events;

use Illuminate\Broadcasting\Channel;
use Illuminate\Http\Request;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PresenceChannel;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class MessagePosted implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $message, $number;

    /**
     * Create a new event instance.
     */
    public function __construct(Request $request)
    {
        $this->message = $request->message;
        $this->number = $request->number;
    }

    public function broadcastWith()
    {
        return [
            'message' => $this->message,
            'number' => $this->number,
        ];
    }
    /**
     * Get the channels the event should broadcast on.
     *
     * @return array<int, Channel>
     */
    public function broadcastOn()
    {
        Log::info('BroadcastOn triggered');
        return new Channel('chat');
    }
}
