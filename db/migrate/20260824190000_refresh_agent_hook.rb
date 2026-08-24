# The comment hook is spliced into the body at write time, so every row still
# carries the script that was current when it was uploaded. Two things break if
# they are left that way: the wrapper's comment overlay never hears back from an
# older hook, so pins for existing comments never appear, and a Markdown
# artifact is served the current script's CSP hash while its body holds the old
# script, which blocks the script outright.
class RefreshAgentHook < ActiveRecord::Migration[8.1]
  def up
    Artifact.find_each(&:refresh_agent_hook!)
  end

  # Nothing to undo: the previous script is not kept anywhere, and re-splicing is
  # what every subsequent write does anyway.
  def down = nil
end
