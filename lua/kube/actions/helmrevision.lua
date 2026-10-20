---A revision row of the history of a Helm release.
---@type Actions
local M = {
  drill_down_resource = function(kbuf, revision)
    require("kube.actions.helmrelease").open(
      kbuf,
      { name = revision.release, namespace = revision.namespace },
      "manifest",
      { revision = revision.revision }
    )
  end,
}

return M
