# The comment-mode cursor moved from `crosshair` to a speech bubble, which lives
# in artifact_agent.js and therefore in every stored row — see AgentInjector.
#
# Batched small on purpose: every row carries its gzipped body, and a 5 MB
# artifact whose payload is a base64 image barely compresses, so the default
# batch of 1000 would pull gigabytes into memory inside the db:prepare that
# runs before the server boots.
class RefreshAgentHookCursor < ActiveRecord::Migration[8.1]
  def up
    Artifact.find_each(batch_size: 50, &:refresh_agent_hook!)
  end

  def down = nil
end
