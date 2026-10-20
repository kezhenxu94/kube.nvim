#!/usr/bin/env bash
# Record the demo with asciinema: a script types into Neovim in tmux, against the
# demo cluster (demo/setup.sh). Usage: demo/record.sh [file.cast]
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
out=${1:-$dir/kube-nvim.cast}
tmux=(tmux -L kube-nvim-demo -f "$dir/tmux.conf")

# Neovim's state (e.g. the context of :Kube context) and data, apart from the user's
xdg=$(mktemp -d)
trap 'rm -rf "$xdg"' EXIT

"${tmux[@]}" kill-server 2>/dev/null || true
"${tmux[@]}" new-session -d -s demo -x 120 -y 32 -c "$(dirname "$dir")" \
  -e KUBECONFIG="$dir/.kubeconfig" -e XDG_STATE_HOME="$xdg/state" -e XDG_DATA_HOME="$xdg/data" \
  -e XDG_CACHE_HOME="$xdg/cache" -e BASH_SILENCE_DEPRECATION_WARNING=1 "bash --rcfile demo/bashrc"

TERM=xterm-256color asciinema rec --headless --overwrite --window-size 120x32 --idle-time-limit 2 \
  --title "kube.nvim" -c "${tmux[*]} attach -t demo" "$out" &
recording=$!
sleep 1

keys() { "${tmux[@]}" send-keys -t demo "$@"; }
typed() {
  local text=$1
  for ((i = 0; i < ${#text}; i++)); do
    keys -l -- "${text:i:1}"
    sleep 0.05
  done
}
run() {
  typed "$1"
  keys Enter
  sleep "${2:-2}"
}

run "nvim" 1
# The resource types: K explains, <CR> lists
run ":e kube://" 3
run "/deployments" 1
keys K && sleep 4
keys l && sleep 1
keys Enter && sleep 3

# Scale by editing DESIRED, :w applies after confirming
run "/web" 1
keys 2W && sleep 1
keys r3 && sleep 1
run ":w" 2
run "1" 3
# The pods of the deployment, watched
keys Enter && sleep 2
keys gw && sleep 12

# Diagnostics on unhealthy pods
run ":e kube://ns/demo/pods" 3
keys ']d' && sleep 1
keys C-w d && sleep 4
keys l && sleep 1

# Logs, made readable with jq
run "/api-" 1
keys gl && sleep 3
run ":%!jq -r .msg" 3
keys C-o && sleep 2

# Code actions, a shell
run "/web-" 1
keys gra && sleep 4
keys Escape && sleep 1
keys gs && sleep 3
run "nginx -v" 2
run "ls /usr/share/nginx/html" 2
keys C-\\ C-n && sleep 1
keys C-o && sleep 2

# Up to the parents: all namespaces, namespaces, resource types
for _ in 1 2 3; do
  keys - && sleep 2
done

# Helm releases: K shows the status, <CR> the manifest, rollback from the history
run ":e kube://ns/demo/helm" 3
run "/storefront" 1
keys K && sleep 4
keys l && sleep 1
keys Enter && sleep 3
keys C-o && sleep 2
keys gra && sleep 3
run "6" 3
keys gg && sleep 1
keys gra && sleep 3
run "1" 2
run "1" 4

keys 'g?' && sleep 5
keys q && sleep 1

run ":qa!" 1
"${tmux[@]}" kill-server
wait "$recording"
echo "Recorded $out"
