# artifact_agent.js now scrolls a thread's spot into view when it is picked from
# the side panel, so existing rows are re-spliced — see the note on
# AgentInjector. Batched small for the same reason as RefreshAgentHookAnchorPoint.
class RefreshAgentHookReveal < ActiveRecord::Migration[8.1]
  def up
    Artifact.find_each(batch_size: 50, &:refresh_agent_hook!)
  end

  def down = nil
end
