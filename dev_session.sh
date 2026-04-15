
#!/bin/bash
# dev-session.sh
# Opens a tmux session with each server in a pane, runs a command then drops to shell
 
SESSION="servers"
 
# ---------------------------------------------------------------------------
# Config — edit these
# ---------------------------------------------------------------------------
 
SERVERS=(
    "madmac@192.168.0.13"
    "madmac@192.168.0.13"
    "root@192.168.0.254"
    "root@192.168.0.254"
)
 
# Command to run on each server after connecting
# Shell stays open after it completes
REMOTE_CMD="docker ps; exec \$SHELL"
 
# Optional: SSH key to use (leave empty to use default)
SSH_KEY="$HOME/.ssh/id_scripts"
 
# ---------------------------------------------------------------------------
# Build SSH command
# ---------------------------------------------------------------------------
 
ssh_cmd() {
    local host="$1"
    if [[ -n "$SSH_KEY" ]]; then
        echo "ssh -i $SSH_KEY -t $host '$REMOTE_CMD'"
    else
        echo "ssh -t $host '$REMOTE_CMD'"
    fi
}
 
# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
 
# Attach to existing session if already running
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' already exists — attaching."
    tmux attach -t "$SESSION"
    exit 0
fi
 
if [[ ${#SERVERS[@]} -eq 0 ]]; then
    echo "No servers defined." >&2
    exit 1
fi
 
# Create session with first server
tmux new-session -d -s "$SESSION" -n "servers"
tmux send-keys -t "$SESSION:servers" "$(ssh_cmd "${SERVERS[0]}")" Enter
 
# Add remaining servers as panes
for i in "${!SERVERS[@]}"; do
    [[ $i -eq 0 ]] && continue  # skip first, already created
    tmux split-window -t "$SESSION:servers" -h
    tmux send-keys -t "$SESSION:servers" "$(ssh_cmd "${SERVERS[$i]}")" Enter
done
 
# Balance panes evenly
tmux select-layout -t "$SESSION:servers" tiled
 
# Focus first pane
tmux select-pane -t "$SESSION:servers.0"
 
tmux attach -t "$SESSION"
