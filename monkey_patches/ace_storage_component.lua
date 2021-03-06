local StorageComponent = require 'stonehearth.components.storage.storage_component'
AceStorageComponent = class()

AceStorageComponent._ace_old_create = StorageComponent.create
function AceStorageComponent:create()
	
	self._is_create = true
	self:_ace_old_create()

end

AceStorageComponent._ace_old_activate = StorageComponent.activate
function AceStorageComponent:activate()	
	
	self:_ace_old_activate()
	
    if self._is_create then
		local json = radiant.entities.get_json(self) or {}	
		if json.default_filter then
			self:set_filter(json.default_filter)
		end
	end

end

return AceStorageComponent