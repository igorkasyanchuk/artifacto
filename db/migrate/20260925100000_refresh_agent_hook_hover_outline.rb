# artifact_agent.js now outlines the element under the pointer in comment mode
# and draws its cursor in the app's own colours, so existing rows are re-spliced
# — see the note on AgentInjector. Batched small for the same reason as
# RefreshAgentHookAnchorPoint.
class RefreshAgentHookHoverOutline < ActiveRecord::Migration[8.1]
  def up
    Artifact.find_each(batch_size: 50, &:refresh_agent_hook!)
  end

  def down = nil
end
