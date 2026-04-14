#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DEST="$HOME/.claude/skills/multi-agent"
SCRIPTS_DEST="$HOME/.claude/scripts/multi-agent"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing multi-agent skill..."
echo ""

# 1. Copy SKILL.md
mkdir -p "$SKILL_DEST"
cp "$REPO_DIR/SKILL.md" "$SKILL_DEST/SKILL.md"
echo "[ok] SKILL.md -> $SKILL_DEST/SKILL.md"

# 2. Copy scripts/ and make executable
mkdir -p "$SCRIPTS_DEST"
for file in "$REPO_DIR/scripts/"*; do
    name="$(basename "$file")"
    cp "$file" "$SCRIPTS_DEST/$name"
    chmod +x "$SCRIPTS_DEST/$name"
    echo "[ok] scripts/$name -> $SCRIPTS_DEST/$name (executable)"
done

# 3. Add allow entries to ~/.claude/settings.json if not already present
if [ ! -f "$SETTINGS" ]; then
    echo '{"permissions":{"allow":[]}}' > "$SETTINGS"
fi

ALLOW_ENTRIES=(
  "Bash(~/.claude/scripts/multi-agent/*)"  # skill scripts
  "Bash(tmux *)"                            # tmux commands used in SKILL.md
  "Bash(cat /tmp/*)"                        # pipe temp files to send-message
  "Bash(rm -f /tmp/*)"                      # clean up temp files after use
  "Write(/tmp/**)"                          # write temp files
  "Edit(/tmp/**)"                           # edit temp files
  # Edit/Write for the working directory are added dynamically at skill load
  # time by scripts/scope-permissions, since the path varies per project.
)

for entry in "${ALLOW_ENTRIES[@]}"; do
    already_present=$(jq --arg e "$entry" \
        '(.permissions.allow // []) | map(select(. == $e)) | length' \
        "$SETTINGS")
    if [ "$already_present" -gt 0 ]; then
        echo "[skip] '$entry' already in $SETTINGS"
    else
        tmp=$(mktemp)
        jq --arg e "$entry" \
            '.permissions.allow = ((.permissions.allow // []) + [$e])' \
            "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
        echo "[ok] Added '$entry' to $SETTINGS"
    fi
done

# 4. Add Stop hook to ~/.claude/settings.json if not already present
MARK_IDLE_CMD="$HOME/.claude/scripts/multi-agent/mark-idle"

stop_hook_present=$(jq --arg cmd "$MARK_IDLE_CMD" \
    '(.hooks.Stop // []) | map(.hooks // [] | map(select(.command == $cmd))) | flatten | length' \
    "$SETTINGS")

if [ "$stop_hook_present" -gt 0 ]; then
    echo "[skip] Stop hook for '$MARK_IDLE_CMD' already in $SETTINGS"
else
    tmp=$(mktemp)
    jq --arg cmd "$MARK_IDLE_CMD" \
        '.hooks.Stop = ((.hooks.Stop // []) + [{"matcher": "", "hooks": [{"type": "command", "command": $cmd, "async": true}]}])' \
        "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "[ok] Added Stop hook -> $MARK_IDLE_CMD"
fi

echo ""
echo "Installation complete."
echo "  Skill:   $SKILL_DEST/SKILL.md"
echo "  Scripts: $SCRIPTS_DEST/"
echo "  Hook:    Stop -> $MARK_IDLE_CMD"
