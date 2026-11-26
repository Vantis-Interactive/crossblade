--!strict
-- Fetches the initial session snapshot once the server has loaded this player's profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Net = require(script.Parent.Parent.Core.Net)

local SnapshotController = {
	Name = "SnapshotController",
	Loaded = Signal.new() :: Signal.Signal<{ [string]: any }>,
	Snapshot = nil :: { [string]: any }?,
}

function SnapshotController.Start(self: typeof(SnapshotController))
	for _ = 1, 60 do
		local snapshot = Net.Invoke("GetSnapshot", {})
		if snapshot then
			self.Snapshot = snapshot
			self.Loaded:Fire(snapshot)
			return
		end
		task.wait(1)
	end
	warn("[Snapshot] server never returned a snapshot; profile may have failed to load")
end

return SnapshotController
